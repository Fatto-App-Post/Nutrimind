using FluentAssertions;
using Nutrimind.Application;
using Nutrimind.Domain;

namespace Nutrimind.Tests.Unit;

public class FoodServiceCachingTests
{
    [Fact]
    public async Task GetByBarcode_caches_off_result_in_repo()
    {
        var offFood = new Food
        {
            Id = Guid.NewGuid(),
            Name = "Cached OFF Food",
            Barcode = "789",
            Source = "openfoodfacts",
            Kcal = 200,
            ProteinG = 20,
            CarbsG = 30,
            FatG = 10
        };

        var repo = new FakeFoodRepository(null);
        var off = new FakeOffClient(offFood);
        var service = new FoodService(repo, off);

        // Prima chiamata: OFF chiamato, risultato cached
        var result1 = await service.GetByBarcodeAsync("789", default);
        result1.Should().NotBeNull();
        off.CallCount.Should().Be(1);
        repo.LastUpserted.Should().NotBeNull();

        // Seconda chiamata: ora il repo restituisce il cached
        repo._local = repo.LastUpserted;
        off.CallCount = 0; // reset

        var result2 = await service.GetByBarcodeAsync("789", default);
        result2.Should().NotBeNull();
        off.CallCount.Should().Be(0); // OFF non più chiamato
    }

    private sealed class FakeFoodRepository : IFoodRepository
    {
        public Food? _local;
        public Food? LastUpserted { get; private set; }

        public FakeFoodRepository(Food? local) => _local = local;

        public Task<Food?> GetByBarcodeAsync(string barcode, CancellationToken ct)
            => Task.FromResult(_local);

        public Task<IReadOnlyList<Food>> SearchAsync(string query, int limit, CancellationToken ct)
            => Task.FromResult<IReadOnlyList<Food>>(Array.Empty<Food>());

        public Task UpsertAsync(Food food, CancellationToken ct)
        {
            LastUpserted = food;
            return Task.CompletedTask;
        }
    }

    private sealed class FakeOffClient : IOpenFoodFactsClient
    {
        private readonly Food? _food;
        public int CallCount { get; set; }

        public FakeOffClient(Food? food) => _food = food;

        public Task<Food?> GetProductByBarcodeAsync(string barcode, CancellationToken ct)
        {
            CallCount++;
            return Task.FromResult(_food);
        }
    }
}
