using Nutrimind.Application;
using Nutrimind.Infrastructure.Supabase;
using Nutrimind.Infrastructure.OpenFoodFacts;
using Supabase;

var builder = WebApplication.CreateBuilder(args);

// Configurazione Supabase
var supabaseUrl = builder.Configuration["Supabase:Url"]!;
var supabaseKey = builder.Configuration["Supabase:ServiceRoleKey"]!;
var options = new SupabaseOptions { AutoConnectRealtime = false };
var supabaseClient = new Client(supabaseUrl, supabaseKey, options);

builder.Services.AddSingleton(supabaseClient);
builder.Services.AddSingleton<IFoodRepository, SupabaseFoodRepository>();

// Configurazione Open Food Facts
var offBaseUri = builder.Configuration["OpenFoodFacts:BaseUri"]!;
builder.Services.AddHttpClient<IOpenFoodFactsClient, OpenFoodFactsClient>(c =>
{
    c.BaseAddress = new Uri(offBaseUri);
    c.DefaultRequestHeaders.UserAgent.ParseAdd(
        builder.Configuration["OpenFoodFacts:UserAgent"] ?? "Nutrimind/0.1");
});

builder.Services.AddScoped<IFoodService, FoodService>();

var app = builder.Build();

app.MapGet("/health", () => Results.Ok(new { Status = "OK" }));

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
