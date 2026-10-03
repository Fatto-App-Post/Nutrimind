using Supabase;
using Supabase.Postgrest;
using Supabase.Postgrest.Models;
using Nutrimind.Domain;
using Nutrimind.Application;

namespace Nutrimind.Infrastructure.Supabase;

public sealed class SupabaseFoodRepository : IFoodRepository
{
    private readonly Supabase.Client _client;

    public SupabaseFoodRepository(Supabase.Client client)
    {
        _client = client;
    }

    public async Task<Food?> GetByBarcodeAsync(string barcode, CancellationToken ct)
    {
        var response = await _client
            .From<FoodRow>()
            .Filter("barcode", Operator.Equals, barcode)
            .Filter("is_active", Operator.Equals, true)
            .Filter("verification", Operator.NotEquals, "rejected")
            .Single(ct: ct);

        return response?.ToDomain();
    }

    public async Task<IReadOnlyList<Food>> SearchAsync(string query, int limit, CancellationToken ct)
    {
        var response = await _client
            .From<FoodRow>()
            .Filter("name_search", Operator.Ilike, $"%{query}%")
            .Limit(limit)
            .Get(ct: ct);

        return response.Models.Select(r => r.ToDomain()).ToList().AsReadOnly();
    }

    public async Task UpsertAsync(Food food, CancellationToken ct)
    {
        var row = FoodRow.FromDomain(food);
        await _client.From<FoodRow>().Upsert(row, ct: ct);
    }
}

public sealed class FoodRow : BaseModel<FoodRow>
{
    [PrimaryKey("id")]
    public Guid id { get; set; }

    [Column("name")]
    public string name { get; set; } = "";

    [Column("brand")]
    public string? brand { get; set; }

    [Column("barcode")]
    public string? barcode { get; set; }

    [Column("source")]
    public string source { get; set; } = "user";

    [Column("source_id")]
    public string? source_id { get; set; }

    [Column("verification")]
    public string verification { get; set; } = "unverified";

    [Column("kcal")]
    public decimal kcal { get; set; }

    [Column("protein_g")]
    public decimal protein_g { get; set; }

    [Column("carbs_g")]
    public decimal carbs_g { get; set; }

    [Column("fat_g")]
    public decimal fat_g { get; set; }

    [Column("image_front_url")]
    public string? image_front_url { get; set; }

    [Column("nutriscore_grade")]
    public string? nutriscore_grade { get; set; }

    [Column("ecoscore_grade")]
    public string? ecoscore_grade { get; set; }

    [Column("nova_group")]
    public int? nova_group { get; set; }

    [Column("is_active")]
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
