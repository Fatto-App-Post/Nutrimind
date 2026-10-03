using Nutrimind.Application;
using Nutrimind.Infrastructure.Supabase;
using Nutrimind.Infrastructure.OpenFoodFacts;

var builder = WebApplication.CreateBuilder(args);

var supabaseUrl = builder.Configuration["Supabase:Url"] ?? throw new InvalidOperationException("Supabase:Url not configured");
var supabaseServiceKey = builder.Configuration["Supabase:ServiceRoleKey"] ?? throw new InvalidOperationException("Supabase:ServiceRoleKey not configured");

builder.Services.AddHttpClient();
builder.Services.AddScoped<IFoodRepository>(sp => new SupabaseFoodRepository(sp.GetRequiredService<IHttpClientFactory>().CreateClient(), supabaseUrl, supabaseServiceKey));

var offBaseUri = builder.Configuration["OpenFoodFacts:BaseUri"] ?? "https://world.openfoodfacts.net";
builder.Services.AddHttpClient<IOpenFoodFactsClient, OpenFoodFactsClient>(c =>
{
    c.BaseAddress = new Uri(offBaseUri);
    c.DefaultRequestHeaders.UserAgent.ParseAdd("Nutrimind/0.1");
});

builder.Services.AddScoped<IFoodService, FoodService>();

var app = builder.Build();

app.MapGet("/health", () => Results.Ok(new { Status = "OK" }));
app.MapGet("/api/foods/search", async (string q, int limit, IFoodService foodService, CancellationToken ct) =>
{
    if (string.IsNullOrWhiteSpace(q)) return Results.BadRequest("Query parameter 'q' is required");
    limit = Math.Clamp(limit, 1, 50);
    return Results.Ok(await foodService.SearchAsync(q, limit, ct));
});
app.MapGet("/api/foods/barcode/{barcode}", async (string barcode, IFoodService foodService, CancellationToken ct) =>
{
    var food = await foodService.GetByBarcodeAsync(barcode, ct);
    return food is null ? Results.NotFound() : Results.Ok(food);
});

app.Run();
