using Supabase;
using Nutrimind.Domain;

namespace Nutrimind.Infrastructure.Supabase;

public sealed class SupabaseFoodRepository : IFoodRepository
{
    private readonly Client _client;

    public SupabaseFoodRepository(Client client)
    {
        _client = client;
    }

    public async Task<Food?> GetByBarcodeAsync(string barcode, CancellationToken ct)
    {
        var response = await _client
            .From<FoodRow>()
            .Where(r => r.barcode == barcode && r.is_active && r.verification != "rejected")
            .Single(ct);

        return response?.ToDomain();
    }

    public async Task<IReadOnlyList<Food>> SearchAsync(string query, int limit, CancellationToken ct)
    {
        var response = await _client
            .From<FoodRow>()
            .Where(r => r.name_search.Contains(query.ToLowerInvariant()))
            .Limit(limit)
            .Select(ct);

        return response.Select(r => r.ToDomain()).ToList().AsReadOnly();
    }

    public async Task UpsertAsync(Food food, CancellationToken ct)
    {
        var row = FoodRow.FromDomain(food);
        await _client.From<FoodRow>().Upsert(row, ct);
    }
}

// Modello interno per Supabase
public sealed class FoodRow
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

    public static FoodRow FromDomain(Food f) => new()
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
