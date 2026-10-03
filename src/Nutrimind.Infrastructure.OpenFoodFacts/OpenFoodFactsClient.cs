using System.Net.Http.Headers;
using System.Text.Json;
using Nutrimind.Domain;

namespace Nutrimind.Infrastructure.OpenFoodFacts;

public interface IOpenFoodFactsClient
{
    Task<Food?> GetProductByBarcodeAsync(string barcode, CancellationToken ct);
}

public sealed class OpenFoodFactsClient : IOpenFoodFactsClient
{
    private readonly HttpClient _http;
    private readonly JsonSerializerOptions _jsonOptions;

    public OpenFoodFactsClient(HttpClient http)
    {
        _http = http;
        _jsonOptions = new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true,
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        };
    }

    public async Task<Food?> GetProductByBarcodeAsync(string barcode, CancellationToken ct)
    {
        var uri = $"/api/v2/product/{barcode}";
        var response = await _http.GetAsync(uri, ct);
        if (!response.IsSuccessStatusCode)
            return null;

        var json = await response.Content.ReadAsStringAsync(ct);
        var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;

        if (!root.TryGetProperty("product", out var product))
            return null;

        if (product.TryGetProperty("status", out var status) &&
            status.GetInt32() == 0)
        {
            // Product not found
            return null;
        }

        // Mappatura OFF -> Food
        var food = new Food
        {
            Id = Guid.NewGuid(),
            Name = GetString(product, "product_name_it")
                    ?? GetString(product, "product_name")
                    ?? GetString(product, "generic_name")
                    ?? "Unknown",
            Brand = GetString(product, "brands_tags")?.Split(',').FirstOrDefault()?.Trim()
                    ?? GetString(product, "brands"),
            Barcode = barcode,
            Source = "openfoodfacts",
            SourceId = barcode,
            Verification = "unverified",
            Kcal = GetNumber(product, "nutriments", "energy-kcal_100g"),
            ProteinG = GetNumber(product, "nutriments", "proteins_100g"),
            CarbsG = GetNumber(product, "nutriments", "carbohydrates_100g"),
            FatG = GetNumber(product, "nutriments", "fat_100g"),
            ImageFrontUrl = GetString(product, "image_front_url"),
            NutriscoreGrade = GetString(product, "nutriscore_grade"),
            EcoscoreGrade = GetString(product, "ecoscore_grade"),
            NovaGroup = GetInt(product, "nova_group")
        };

        return food;
    }

    private static string? GetString(JsonElement elem, string prop)
        => elem.TryGetProperty(prop, out var v) && v.ValueKind == JsonValueKind.String
            ? v.GetString()
            : null;

    private static string? GetString(JsonElement elem, string p1, string p2)
        => elem.TryGetProperty(p1, out var inner) && inner.ValueKind == JsonValueKind.Object
            ? GetString(inner, p2)
            : null;

    private static decimal GetNumber(JsonElement elem, string p1, string p2)
        => elem.TryGetProperty(p1, out var inner)
           && inner.TryGetProperty(p2, out var v)
           && v.TryGetDecimal(out var d)
            ? d
            : 0m;

    private static int? GetInt(JsonElement elem, string prop)
        => elem.TryGetProperty(prop, out var v) && v.TryGetInt32(out var i) ? i : null;
}
