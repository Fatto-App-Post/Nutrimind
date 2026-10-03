using Nutrimind.Domain;

namespace Nutrimind.Application;

public interface IFoodService
{
    Task<Food?> GetByBarcodeAsync(string barcode, CancellationToken ct);
    Task<IReadOnlyList<Food>> SearchAsync(string query, int limit, CancellationToken ct);
}
