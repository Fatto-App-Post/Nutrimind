namespace Nutrimind.Domain;

public interface IFoodRepository
{
    Task<IReadOnlyList<Food>> ListAsync(int limit, CancellationToken ct = default);
    Task<IReadOnlyList<Food>> SearchAsync(string query, int limit, CancellationToken ct = default);
    Task<Food?> GetByIdAsync(Guid id, CancellationToken ct = default);
    Task<Food?> GetByBarcodeAsync(string barcode, CancellationToken ct = default);
    Task<Food> CreateAsync(Food food, CancellationToken ct = default);
    Task<Food?> UpdateAsync(Guid id, Food food, CancellationToken ct = default);
    Task<bool> DeleteAsync(Guid id, CancellationToken ct = default);
}

public interface IOpenFoodFactsClient
{
    Task<Food?> GetProductByBarcodeAsync(string barcode, CancellationToken ct);
}
