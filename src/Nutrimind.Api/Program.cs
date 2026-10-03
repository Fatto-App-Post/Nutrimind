using Nutrimind.Application;
using Nutrimind.Infrastructure.Supabase;
using Nutrimind.Infrastructure.OpenFoodFacts;

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

// Configura HttpClient
builder.Services.AddHttpClient();

builder.Services.AddScoped<IFoodRepository>(sp =>
{
    var httpClientFactory = sp.GetRequiredService<IHttpClientFactory>();
    var client = httpClientFactory.CreateClient();
    return new SupabaseFoodRepository(client, supabaseUrl, supabaseServiceKey);
});

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
