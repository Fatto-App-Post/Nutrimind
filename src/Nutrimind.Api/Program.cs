using Nutrimind.Domain;
using Nutrimind.Application;
using Nutrimind.Infrastructure.Supabase;
using Nutrimind.Infrastructure.OpenFoodFacts;
using Supabase;

var builder = WebApplication.CreateBuilder(args);

// ==========================================
// Configurazione Supabase
// ==========================================
var supabaseUrl = builder.Configuration["Supabase:Url"] 
    ?? Environment.GetEnvironmentVariable("Supabase__Url") 
    ?? throw new InvalidOperationException("Supabase:Url not configured");

var supabaseServiceKey = builder.Configuration["Supabase:ServiceRoleKey"] 
    ?? Environment.GetEnvironmentVariable("Supabase__ServiceRoleKey") 
    ?? throw new InvalidOperationException("Supabase:ServiceRoleKey not configured");

var supabasePublishableKey = builder.Configuration["Supabase:PublishableKey"] 
    ?? Environment.GetEnvironmentVariable("Supabase__PublishableKey");

var supabaseJwksUrl = builder.Configuration["Supabase:JwksUrl"] 
    ?? Environment.GetEnvironmentVariable("Supabase__JwksUrl");

var options = new SupabaseOptions 
{ 
    AutoConnectRealtime = false,
    AutoRefreshToken = true
};

var supabaseClient = new Client(supabaseUrl, supabaseServiceKey, options);

builder.Services.AddSingleton(supabaseClient);
builder.Services.AddSingleton<IFoodRepository, SupabaseFoodRepository>();

// Log configurazione (solo in Development)
if (builder.Environment.IsDevelopment())
{
    Console.WriteLine($"[DEV] Supabase URL: {supabaseUrl}");
    Console.WriteLine($"[DEV] Supabase JWKS: {supabaseJwksUrl ?? "not configured"}");
}

// ==========================================
// Configurazione Open Food Facts
// ==========================================
var offBaseUri = builder.Configuration["OpenFoodFacts:BaseUri"] 
    ?? Environment.GetEnvironmentVariable("OpenFoodFacts__BaseUri") 
    ?? "https://world.openfoodfacts.net";

builder.Services.AddHttpClient<IOpenFoodFactsClient, OpenFoodFactsClient>(c =>
{
    c.BaseAddress = new Uri(offBaseUri);
    var userAgent = builder.Configuration["OpenFoodFacts:UserAgent"] 
        ?? Environment.GetEnvironmentVariable("OpenFoodFacts__UserAgent") 
        ?? "Nutrimind/0.1";
    c.DefaultRequestHeaders.UserAgent.ParseAdd(userAgent);
});

// Log configurazione OFF (solo in Development)
if (builder.Environment.IsDevelopment())
{
    Console.WriteLine($"[DEV] Open Food Facts BaseUri: {offBaseUri}");
}

// ==========================================
// Servizi Application
// ==========================================
builder.Services.AddScoped<IFoodService, FoodService>();

// ==========================================
// API Endpoints
// ==========================================
var app = builder.Build();

app.MapGet("/health", () => Results.Ok(new { 
    Status = "OK", 
    Environment = builder.Environment.EnvironmentName,
    SupabaseUrl = supabaseUrl,
    OffBaseUri = offBaseUri
}));

app.MapGet("/api/foods/search", async (
    string q,
    int limit,
    IFoodService foodService,
    CancellationToken ct) =>
{
    if (string.IsNullOrWhiteSpace(q))
        return Results.BadRequest("Query parameter 'q' is required");

    limit = Math.Clamp(limit, 1, 50);
    var foods = await foodService.SearchAsync(q, limit, ct);
    return Results.Ok(foods);
});

app.MapGet("/api/foods/barcode/{barcode}", async (
    string barcode,
    IFoodService foodService,
    CancellationToken ct) =>
{
    var food = await foodService.GetByBarcodeAsync(barcode, ct);
    return food is null ? Results.NotFound() : Results.Ok(food);
});

app.Run();

public partial class Program { }
