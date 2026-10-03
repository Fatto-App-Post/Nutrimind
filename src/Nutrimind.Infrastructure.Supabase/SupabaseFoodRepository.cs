using Nutrimind.Domain;
using Supabase;
using Postgrest.Models;
using Postgrest.Attributes;

namespace Nutrimind.Infrastructure.Supabase;

public sealed class SupabaseFoodRepository : IFoodRepository
{
    private readonly Client _client;

    public SupabaseFoodRepository(Client client)
    {
        _client = client;
    }

    public async Task<IReadOnlyList<Food>> ListAsync(int limit, CancellationToken ct = default)
    {
        var response = await _client.From<FoodEntity>().Limit(limit).Get();
        return response.Models.Select(ToDomain).ToList();
    }

    public async Task<IReadOnlyList<Food>> SearchAsync(string query, int limit, CancellationToken ct = default)
    {
        var response = await _client.From<FoodEntity>()
            .Where(x => x.Name.Contains(query))
            .Limit(limit)
            .Get();
        return response.Models.Select(ToDomain).ToList();
    }

    public async Task<Food?> GetByIdAsync(Guid id, CancellationToken ct = default)
    {
        var response = await _client.From<FoodEntity>().Where(x => x.Id == id).Single();
        return response is null ? null : ToDomain(response);
    }

    public async Task<Food?> GetByBarcodeAsync(string barcode, CancellationToken ct = default)
    {
        var response = await _client.From<FoodEntity>().Where(x => x.Barcode == barcode).Single();
        return response is null ? null : ToDomain(response);
    }

    public async Task<Food> CreateAsync(Food food, CancellationToken ct = default)
    {
        var entity = FromDomain(food);
        var response = await _client.From<FoodEntity>().Insert(entity);
        return ToDomain(response.Models.First());
    }

    public async Task<Food?> UpdateAsync(Guid id, Food food, CancellationToken ct = default)
    {
        var entity = FromDomain(food);
        var response = await _client.From<FoodEntity>().Where(x => x.Id == id).Update(entity);
        return response.Models.FirstOrDefault() is { } m ? ToDomain(m) : null;
    }

    public async Task<bool> DeleteAsync(Guid id, CancellationToken ct = default)
    {
        await _client.From<FoodEntity>().Where(x => x.Id == id).Delete();
        return true;
    }

    private static Food ToDomain(FoodEntity e) => new()
    {
        Id = e.Id,
        Name = e.Name,
        Brand = e.Brand,
        Barcode = e.Barcode,
        Source = e.Source,
        SourceId = e.SourceId,
        Verification = e.Verification,
        Kcal = e.Kcal,
        ProteinG = e.ProteinG,
        CarbsG = e.CarbsG,
        FatG = e.FatG,
        ImageFrontUrl = e.ImageFrontUrl,
        NutriscoreGrade = e.NutriscoreGrade,
        EcoscoreGrade = e.EcoscoreGrade,
        NovaGroup = e.NovaGroup
    };

    private static FoodEntity FromDomain(Food f) => new()
    {
        Id = f.Id,
        Name = f.Name,
        Brand = f.Brand,
        Barcode = f.Barcode,
        Source = f.Source,
        SourceId = f.SourceId,
        Verification = f.Verification,
        Kcal = f.Kcal,
        ProteinG = f.ProteinG,
        CarbsG = f.CarbsG,
        FatG = f.FatG,
        ImageFrontUrl = f.ImageFrontUrl,
        NutriscoreGrade = f.NutriscoreGrade,
        EcoscoreGrade = f.EcoscoreGrade,
        NovaGroup = f.NovaGroup
    };
}

[Table("foods")]
public class FoodEntity : BaseModel
{
    [PrimaryKey("id", false)]
    public Guid Id { get; set; }

    [Column("name")]
    public string Name { get; set; } = "";

    [Column("brand")]
    public string? Brand { get; set; }

    [Column("barcode")]
    public string? Barcode { get; set; }

    [Column("source")]
    public string Source { get; set; } = "";

    [Column("source_id")]
    public string SourceId { get; set; } = "";

    [Column("verification")]
    public string Verification { get; set; } = "";

    [Column("kcal")]
    public decimal Kcal { get; set; }

    [Column("protein_g")]
    public decimal ProteinG { get; set; }

    [Column("carbs_g")]
    public decimal CarbsG { get; set; }

    [Column("fat_g")]
    public decimal FatG { get; set; }

    [Column("image_front_url")]
    public string? ImageFrontUrl { get; set; }

    [Column("nutriscore_grade")]
    public string? NutriscoreGrade { get; set; }

    [Column("ecoscore_grade")]
    public string? EcoscoreGrade { get; set; }

    [Column("nova_group")]
    public int? NovaGroup { get; set; }
}
