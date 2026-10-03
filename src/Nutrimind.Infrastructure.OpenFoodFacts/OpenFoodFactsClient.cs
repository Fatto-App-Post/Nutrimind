using Nutrimind.Domain;

namespace Nutrimind.Infrastructure.OpenFoodFacts;

public interface IOpenFoodFactsClient
{
    Task<Food?> GetProductByBarcodeAsync(string barcode, CancellationToken ct);
}

public sealed class OpenFoodFactsClient : IOpenFoodFactsClient
{
    private readonly HttpClient _http;
    private readonly string _baseUri;

    public OpenFoodFactsClient(HttpClient http, string baseUri)
    {
        _http = http;
        _baseUri = baseUri.TrimEnd('/');
    }

    public async Task<Food?> GetProductByBarcodeAsync(string barcode, CancellationToken ct)
    {
        var uri = $"{_baseUri}/api/v2/product/{barcode}";
        var response = await _http.GetAsync(uri, ct);
        if (!response.IsSuccessStatusCode) return null;

        // Qui verrà aggiunto il mapping da JSON OFF a Food
        throw new NotImplementedException("Mapping OFF -> Food da implementare");
    }
}
