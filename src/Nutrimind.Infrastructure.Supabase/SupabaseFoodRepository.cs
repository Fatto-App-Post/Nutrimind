using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using System.Web;
using Nutrimind.Domain;
using Nutrimind.Application;

namespace Nutrimind.Infrastructure.Supabase;

public sealed class SupabaseFoodRepository : IFoodRepository
{
    private readonly HttpClient _http;
    private readonly string _baseUrl;
    private readonly string _apiKey;

    public SupabaseFoodRepository(HttpClient http, string baseUrl, string apiKey)
    {
        _http = http;
        _baseUrl = baseUrl.TrimEnd('/');
        _apiKey = apiKey;
        _http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);
        _http.DefaultRequestHeaders.Add("apikey", apiKey);
    }

    public async Task<Food?> GetByBarcodeAsync(string barcode, CancellationToken ct)
    {
        var url = $"{_baseUrl}/rest/v1/foods?barcode=eq.{barcode}&is_active=eq.true&verification=not.eq.rejected&select=*";
        var response = await _http.GetAsync(url, ct);
        if (!response.IsSuccessStatusCode)
            return null;

        var foods = await response.Content.ReadFromJsonAsync<List<FoodDto>>(ct);
        return foods?.FirstOrDefault()?.ToDomain();
    }

    public async Task<IReadOnlyList<Food>> SearchAsync(string query, int limit, CancellationToken ct)
    {
        var encodedQuery = HttpUtility.UrlEncode($"%{query.ToLower()}%");
        var url = $"{_baseUrl}/rest/v1/foods?name_search=ilike.{encodedQuery}&limit={limit}&select=*";
        var response = await _http.GetAsync(url, ct);
        if (!response.IsSuccessStatusCode)
            return new List<Food>();

        var foods = await response.Content.ReadFromJsonAsync<List<FoodDto>>(ct);
        return foods?.Select(f => f.ToDomain()).ToList() ?? new List<Food>();
    }

    public async Task UpsertAsync(Food food, CancellationToken ct)
    {
        var dto = FoodDto.FromDomain(food);
        var url = $"{_baseUrl}/rest/v1/foods";
        var content = new StringContent(
            JsonSerializer.Serialize(dto, new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower }),
            Encoding.UTF8,
            "application/json");

        content.Headers.Add("Prefer", "resolution=merge-duplicates");

        var response = await _http.PostAsync(url, content, ct);
        response.EnsureSuccessStatusCode();
    }
}

// DTO per la serializzazione/deserializzazione
public sealed class FoodDto
{
    public Guid id { get; set; }
    public string name { get; set; } = "";
    public string? brand { get; set; }
    public string? barcode { get; set; }
    public string source { get; set; } = "user";
    public string? source_id { get; set; }
    public string verification { get; set; } = "unverified";
    public decimal kcal { get; set; }
    public decimal protein_g { get; set; }
    public decimal carbs_g { get; set; }
    public decimal fat_g { get; set; }
    public string? image_front_url { get; set; }
    public string? nutriscore_grade { get; set; }
    public string? ecoscore_grade { get; set; }
    public int? nova_group { get; set; }
    public bool is_active { get; set; } = true;

    public Food ToDomain() => new()
    {
        Id = id,
        Name = name,
        Brand = brand,
        Barcode = barcode,
        Source = source,
        SourceId = source_id,
        Verification = verification,
        Kcal = kcal,
        ProteinG = protein_g,
        CarbsG = carbs_g,
        FatG = fat_g,
        ImageFrontUrl = image_front_url,
        NutriscoreGrade = nutriscore_grade,
        EcoscoreGrade = ecoscore_grade,
        NovaGroup = nova_group
    };

    public static FoodDto FromDomain(Food f) => new()
    {
        id = f.Id,
        name = f.Name,
        brand = f.Brand,
        barcode = f.Barcode,
        source = f.Source,
        source_id = f.SourceId,
        verification = f.Verification,
        kcal = f.Kcal,
        protein_g = f.ProteinG,
        carbs_g = f.CarbsG,
        fat_g = f.FatG,
        image_front_url = f.ImageFrontUrl,
        nutriscore_grade = f.NutriscoreGrade,
        ecoscore_grade = f.EcoscoreGrade,
        nova_group = f.NovaGroup,
        is_active = true
    };
}
