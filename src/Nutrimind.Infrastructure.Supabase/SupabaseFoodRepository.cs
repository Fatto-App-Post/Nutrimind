using Nutrimind.Domain;
using Supabase;

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
        var response = await _client.From<FoodEntity>().Limit(limit).Select();
        return response.Models.Select(ToDomain).ToList();
    }

    public async Task<IReadOnlyList<Food>> SearchAsync(string query, int limit, CancellationToken ct = default)
    {
        var response = await _client.From<FoodEntity>()
            .Where(x => x.Name.Contains(query))
            .Limit(limit)
            .Select();
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
        var response = await _client.From<FoodEntity>().Where(x => x.Id == id).Delete();
        return response.Models.Any();
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

public class FoodEntity
{
    public Guid Id { get; set; }
    public string Name { get; set; } = "";
    public string? Brand { get; set; }
    public string? Barcode { get; set; }
    public string Source { get; set; } = "";
    public string SourceId { get; set; } = "";
    public string Verification { get; set; } = "";
    public decimal Kcal { get; set; }
    public decimal ProteinG { get; set; }
    public decimal CarbsG { get; set; }
    public decimal FatG { get; set; }
    public string? ImageFrontUrl { get; set; }
    public string? NutriscoreGrade { get; set; }
    public string? EcoscoreGrade { get; set; }
    public int? NovaGroup { get; set; }
}
