using Nutrimind.Domain;

namespace Nutrimind.Application;

public sealed class FoodService : IFoodService
{
    private readonly IFoodRepository _foodRepository;
    private readonly IOpenFoodFactsClient _offClient;

    public FoodService(IFoodRepository foodRepository, IOpenFoodFactsClient offClient)
    {
        _foodRepository = foodRepository;
        _offClient = offClient;
    }

    public async Task<Food?> GetByBarcodeAsync(string barcode, CancellationToken ct)
    {
        var local = await _foodRepository.GetByBarcodeAsync(barcode, ct);
        if (local is not null)
            return local;

        var off = await _offClient.GetProductByBarcodeAsync(barcode, ct);
        if (off is null)
            return null;

        await _foodRepository.UpsertAsync(off, ct);
        return off;
    }

    public async Task<IReadOnlyList<Food>> SearchAsync(string query, int limit, CancellationToken ct)
    {
        return await _foodRepository.SearchAsync(query, limit, ct);
    }
}

public interface IFoodRepository
{
    Task<Food?> GetByBarcodeAsync(string barcode, CancellationToken ct);
    Task<IReadOnlyList<Food>> SearchAsync(string query, int limit, CancellationToken ct);
    Task UpsertAsync(Food food, CancellationToken ct);
}
