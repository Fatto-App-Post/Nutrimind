using Nutrimind.Domain;

namespace Nutrimind.Application;

public interface IFoodService
{
    Task<IReadOnlyList<Food>> SearchAsync(string? query, int limit = 20, CancellationToken ct = default);
    Task<Food?> GetAsync(Guid id, CancellationToken ct = default);
    Task<Food?> GetByBarcodeAsync(string barcode, CancellationToken ct = default);
    Task<Food> CreateAsync(Food food, CancellationToken ct = default);
    Task<Food?> UpdateAsync(Guid id, Food food, CancellationToken ct = default);
    Task<bool> DeleteAsync(Guid id, CancellationToken ct = default);
}

public sealed class FoodService : IFoodService
{
    private readonly IFoodRepository _repo;
    private readonly IOpenFoodFactsClient? _off;

    public FoodService(IFoodRepository repo, IOpenFoodFactsClient? off = null)
    {
        _repo = repo;
        _off = off;
    }

    public async Task<IReadOnlyList<Food>> SearchAsync(string? query, int limit = 20, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(query))
            return await _repo.ListAsync(limit, ct);

        var results = await _repo.SearchAsync(query, limit, ct);
        if (results.Count > 0 || _off is null)
            return results;

        // Fallback a OpenFoodFacts
        var fallback = await _off.GetProductByBarcodeAsync(query, ct);
        return fallback is not null ? new[] { fallback } : Array.Empty<Food>();
    }

    public Task<Food?> GetAsync(Guid id, CancellationToken ct = default)
        => _repo.GetByIdAsync(id, ct);

    public Task<Food?> GetByBarcodeAsync(string barcode, CancellationToken ct = default)
        => _repo.GetByBarcodeAsync(barcode, ct);

    public Task<Food> CreateAsync(Food food, CancellationToken ct = default)
        => _repo.CreateAsync(food, ct);

    public Task<Food?> UpdateAsync(Guid id, Food food, CancellationToken ct = default)
        => _repo.UpdateAsync(id, food, ct);

    public Task<bool> DeleteAsync(Guid id, CancellationToken ct = default)
        => _repo.DeleteAsync(id, ct);
}
