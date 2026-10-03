using Nutrimind.Application;
using Nutrimind.Infrastructure.Supabase;
using Nutrimind.Infrastructure.OpenFoodFacts;

var builder = WebApplication.CreateBuilder(args);

// Services
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// Domain services
builder.Services.AddScoped<IFoodService, FoodService>();

// Repositories
builder.Services.AddScoped<IFoodRepository, SupabaseFoodRepository>();

// External clients
builder.Services.AddHttpClient<IOpenFoodFactsClient, OpenFoodFactsClient>(c =>
{
    c.BaseAddress = new Uri("https://world.openfoodfacts.org");
});

// Supabase
builder.Services.AddSupabase(builder.Configuration);

var app = builder.Build();

// Middleware
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();

// Health check
app.MapGet("/health", () => Results.Ok(new { Status = "Healthy", Timestamp = DateTime.UtcNow }))
   .WithName("Health")
   .WithOpenApi();

// Food endpoints
var foods = app.MapGroup("/api/foods");

foods.MapGet("", async (IFoodService service, string? query, CancellationToken ct) =>
{
    var foods = await service.SearchFoodsAsync(query, ct);
    return Results.Ok(foods);
})
.WithName("SearchFoods")
.WithOpenApi();

foods.MapGet("{id:guid}", async (IFoodService service, Guid id, CancellationToken ct) =>
{
    var food = await service.GetFoodByIdAsync(id, ct);
    return food is not null ? Results.Ok(food) : Results.NotFound();
})
.WithName("GetFood")
.WithOpenApi();

foods.MapPost("", async (IFoodService service, Food food, CancellationToken ct) =>
{
    var created = await service.CreateFoodAsync(food, ct);
    return Results.Created($"/api/foods/{created.Id}", created);
})
.WithName("CreateFood")
.WithOpenApi();

foods.MapPut("{id:guid}", async (IFoodService service, Guid id, Food food, CancellationToken ct) =>
{
    var updated = await service.UpdateFoodAsync(id, food, ct);
    return updated is not null ? Results.Ok(updated) : Results.NotFound();
})
.WithName("UpdateFood")
.WithOpenApi();

foods.MapDelete("{id:guid}", async (IFoodService service, Guid id, CancellationToken ct) =>
{
    var deleted = await service.DeleteFoodAsync(id, ct);
    return deleted ? Results.NoContent() : Results.NotFound();
})
.WithName("DeleteFood")
.WithOpenApi();

app.Run();

// Make Program visible to integration tests
public partial class Program { }
