namespace Nutrimind.Domain;

public interface IOpenFoodFactsClient
{
    Task<Food?> GetProductByBarcodeAsync(string barcode, CancellationToken ct);
}
