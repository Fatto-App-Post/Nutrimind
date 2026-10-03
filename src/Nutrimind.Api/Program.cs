var builder = WebApplication.CreateBuilder(args);

// TODO: configurare Supabase e OpenFoodFacts

var app = builder.Build();

app.MapGet("/health", () => Results.Ok(new { Status = "OK" }));

app.Run();
