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
builder.Services.AddScoped<IUserService, UserService>();

// Repositories
builder.Services.AddScoped<IFoodRepository, SupabaseFoodRepository>(sp =>
{
    var config = sp.GetRequiredService<IConfiguration>();
    var supabaseUrl = config["Supabase:Url"] ?? throw new InvalidOperationException("Supabase:Url missing");
    var supabaseKey = config["Supabase:Key"] ?? throw new InvalidOperationException("Supabase:Key missing");
    var client = new Client(supabaseUrl, supabaseKey);
    return new SupabaseFoodRepository(client);
});

builder.Services.AddScoped<IUserRepository, SupabaseUserRepository>(sp =>
{
    var config = sp.GetRequiredService<IConfiguration>();
    var supabaseUrl = config["Supabase:Url"] ?? throw new InvalidOperationException("Supabase:Url missing");
    var supabaseKey = config["Supabase:Key"] ?? throw new InvalidOperationException("Supabase:Key missing");
    var client = new Client(supabaseUrl, supabaseKey);
    return new SupabaseUserRepository(client);
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

app.UseHttpsRedirection();

// Health check
app.MapGet("/health", () => Results.Ok(new { Status = "Healthy", Timestamp = DateTime.UtcNow }))
   .WithName("Health")
   .WithOpenApi();

// ==================== FOOD ENDPOINTS ====================
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

foods.MapGet("barcode/{barcode}", async (IFoodService service, string barcode, CancellationToken ct) =>
{
    try
    {
        var food = await service.GetByBarcodeAsync(barcode, ct);
        if (food is not null)
            return Results.Ok(food);
        
        var results = await service.SearchAsync(barcode, 1, ct);
        return results.FirstOrDefault() is { } f ? Results.Ok(f) : Results.NotFound();
    }
    catch (Exception ex)
    {
        app.Logger.LogError(ex, "Error fetching food by barcode {Barcode}", barcode);
        return Results.Problem("Internal server error");
    }
})
.WithName("GetFoodByBarcode")
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

// ==================== USER/AUTH ENDPOINTS ====================
var auth = app.MapGroup("/api/auth");

auth.MapPost("/register", async (IUserService service, RegisterRequest request, CancellationToken ct) =>
{
    try
    {
        var result = await service.RegisterAsync(request, ct);
        return Results.Ok(result);
    }
    catch (Exception ex) when (ex.Message.Contains("already"))
    {
        return Results.Conflict(new { error = "email_exists", message = "Email già registrata" });
    }
})
.WithName("Register")
.WithOpenApi();

auth.MapPost("/login", async (IUserService service, LoginRequest request, CancellationToken ct) =>
{
    try
    {
        var result = await service.LoginAsync(request, ct);
        return Results.Ok(result);
    }
    catch (Exception ex) when (ex.Message.Contains("Invalid"))
    {
        return Results.Unauthorized();
    }
})
.WithName("Login")
.WithOpenApi();

auth.MapPost("/logout", async (IUserService service, CancellationToken ct) =>
{
    await service.LogoutAsync(ct);
    return Results.Ok();
})
.WithName("Logout")
.WithOpenApi();

// User endpoints
var users = app.MapGroup("/api/users");

users.MapGet("/me", async (IUserService service, CancellationToken ct) =>
{
    // Placeholder: in produzione estrarre userId dal token
    var userId = Guid.Parse("00000000-0000-0000-0000-000000000000");
    var result = await service.GetProfileAsync(userId, ct);
    return Results.Ok(result);
})
.WithName("GetCurrentUser")
.WithOpenApi();

users.MapPut("/me", async (IUserService service, UpdateProfileRequest request, CancellationToken ct) =>
{
    var userId = Guid.Parse("00000000-0000-0000-0000-000000000000");
    var result = await service.UpdateProfileAsync(userId, request, ct);
    return Results.Ok(result);
})
.WithName("UpdateCurrentUser")
.WithOpenApi();

// Patient settings
users.MapGet("/me/patient-settings", async (IUserService service, CancellationToken ct) =>
{
    var userId = Guid.Parse("00000000-0000-0000-0000-000000000000");
    var result = await service.GetPatientSettingsAsync(userId, ct);
    return Results.Ok(result);
})
.WithName("GetPatientSettings")
.WithOpenApi();

users.MapPut("/me/patient-settings", async (IUserService service, UpdatePatientSettingsRequest request, CancellationToken ct) =>
{
    var userId = Guid.Parse("00000000-0000-0000-0000-000000000000");
    var result = await service.UpdatePatientSettingsAsync(userId, request, ct);
    return Results.Ok(result);
})
.WithName("UpdatePatientSettings")
.WithOpenApi();

// Nutritionist details
users.MapGet("/me/nutritionist-details", async (IUserService service, CancellationToken ct) =>
{
    var userId = Guid.Parse("00000000-0000-0000-0000-000000000000");
    var result = await service.GetNutritionistDetailsAsync(userId, ct);
    return Results.Ok(result);
})
.WithName("GetNutritionistDetails")
.WithOpenApi();

users.MapPut("/me/nutritionist-details", async (IUserService service, UpdateNutritionistDetailsRequest request, CancellationToken ct) =>
{
    var userId = Guid.Parse("00000000-0000-0000-0000-000000000000");
    var result = await service.UpdateNutritionistDetailsAsync(userId, request, ct);
    return Results.Ok(result);
})
.WithName("UpdateNutritionistDetails")
.WithOpenApi();

// Professional verification
users.MapGet("/me/verification", async (IUserService service, CancellationToken ct) =>
{
    var userId = Guid.Parse("00000000-0000-0000-0000-000000000000");
    var result = await service.GetVerificationAsync(userId, ct);
    return result is not null ? Results.Ok(result) : Results.NotFound();
})
.WithName("GetVerification")
.WithOpenApi();

users.MapPost("/me/verification", async (IUserService service, RequestVerificationRequest request, CancellationToken ct) =>
{
    var userId = Guid.Parse("00000000-0000-0000-0000-000000000000");
    var result = await service.RequestVerificationAsync(userId, request, ct);
    return Results.Ok(result);
})
.WithName("RequestVerification")
.WithOpenApi();

// Invitations
users.MapPost("/invitations", async (IUserService service, CancellationToken ct) =>
{
    var nutritionistId = Guid.Parse("00000000-0000-0000-0000-000000000000");
    var result = await service.CreateInvitationAsync(nutritionistId, ct);
    return Results.Ok(result);
})
.WithName("CreateInvitation")
.WithOpenApi();

users.MapPost("/invitations/redeem", async (IUserService service, RedeemInvitationRequest request, CancellationToken ct) =>
{
    var patientId = Guid.Parse("00000000-0000-0000-0000-000000000000");
    var result = await service.RedeemInvitationAsync(patientId, request, ct);
    return Results.Ok(result);
})
.WithName("RedeemInvitation")
.WithOpenApi();

// Links
users.MapDelete("/links/{linkId:guid}", async (IUserService service, Guid linkId, CancellationToken ct) =>
{
    var userId = Guid.Parse("00000000-0000-0000-0000-000000000000");
    var result = await service.RevokeLinkAsync(linkId, userId, ct);
    return result ? Results.NoContent() : Results.NotFound();
})
.WithName("RevokeLink")
.WithOpenApi();

// Consents
users.MapPost("/consents", async (IUserService service, GrantConsentRequest request, CancellationToken ct) =>
{
    var userId = Guid.Parse("00000000-0000-0000-0000-000000000000");
    var result = await service.GrantConsentAsync(userId, request, ct);
    return result ? Results.NoContent() : Results.BadRequest();
})
.WithName("GrantConsent")
.WithOpenApi();

users.MapDelete("/consents", async (IUserService service, RevokeConsentRequest request, CancellationToken ct) =>
{
    var userId = Guid.Parse("00000000-0000-0000-0000-000000000000");
    var result = await service.RevokeConsentAsync(userId, request, ct);
    return result ? Results.NoContent() : Results.BadRequest();
})
.WithName("RevokeConsent")
.WithOpenApi();

app.Run();

// Make Program visible to integration tests
public partial class Program { }
