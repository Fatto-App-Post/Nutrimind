using Nutrimind.Application;
using Nutrimind.Domain;
using Nutrimind.Infrastructure.Supabase;
using OpenFoodFactsClient = Nutrimind.Infrastructure.OpenFoodFacts.OpenFoodFactsClient;
using IOpenFoodFactsClient = Nutrimind.Infrastructure.OpenFoodFacts.IOpenFoodFactsClient;
using Supabase;

var builder = WebApplication.CreateBuilder(args);

// Services
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// Domain services
builder.Services.AddScoped<IFoodService, FoodService>();

// Repositories
builder.Services.AddScoped<IFoodRepository, SupabaseFoodRepository>(sp =>
{
    var config = sp.GetRequiredService<IConfiguration>();
    var supabaseUrl = config["Supabase:Url"] ?? throw new InvalidOperationException("Supabase:Url missing");
    var supabaseKey = config["Supabase:Key"] ?? throw new InvalidOperationException("Supabase:Key missing");
    var client = new Client(supabaseUrl, supabaseKey);
    return new SupabaseFoodRepository(client);
});

// External clients
builder.Services.AddHttpClient<IOpenFoodFactsClient, OpenFoodFactsClient>(c =>
{
    c.BaseAddress = new Uri("https://world.openfoodfacts.org");
    return new OpenFoodFactsClient(c);
});

var app = builder.Build();

// Middleware
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}
else
{
    app.UseHttpsRedirection();
}

// Health check
app.MapGet("/health", () => Results.Ok(new { Status = "Healthy", Timestamp = DateTime.UtcNow }))
   .WithName("Health")
   .WithOpenApi();

// Food endpoints
var foods = app.MapGroup("/api/foods");

foods.MapGet("", async (IFoodService service, string? query, CancellationToken ct) =>
{
    var foods = await service.SearchAsync(query, 20, ct);
    return Results.Ok(foods);
})
.WithName("SearchFoods")
.WithOpenApi();

foods.MapGet("{id:guid}", async (IFoodService service, Guid id, CancellationToken ct) =>
{
    var food = await service.GetAsync(id, ct);
    return food is not null ? Results.Ok(food) : Results.NotFound();
})
.WithName("GetFood")
.WithOpenApi();

foods.MapPost("", async (IFoodService service, Food food, CancellationToken ct) =>
{
    var created = await service.CreateAsync(food, ct);
    return Results.Created($"/api/foods/{created.Id}", created);
})
.WithName("CreateFood")
.WithOpenApi();

foods.MapPut("{id:guid}", async (IFoodService service, Guid id, Food food, CancellationToken ct) =>
{
    var updated = await service.UpdateAsync(id, food, ct);
    return updated is not null ? Results.Ok(updated) : Results.NotFound();
})
.WithName("UpdateFood")
.WithOpenApi();

foods.MapDelete("{id:guid}", async (IFoodService service, Guid id, CancellationToken ct) =>
{
    var deleted = await service.DeleteAsync(id, ct);
    return deleted ? Results.NoContent() : Results.NotFound();
})
.WithName("DeleteFood")
.WithOpenApi();

app.Run();

// Make Program visible to integration tests
public partial class Program { }
