using FluentAssertions;
using Nutrimind.Application;
using Nutrimind.Domain;

namespace Nutrimind.Tests.Unit;

public class FoodServiceTests
{
    [Fact]
    public async Task GetByBarcode_returns_local_food_when_exists()
    {
        var localFood = new Food
        {
            Id = Guid.NewGuid(),
            Name = "Local Food",
            Barcode = "123",
            Source = "user",
            Kcal = 100,
            ProteinG = 10,
            CarbsG = 20,
            FatG = 5
        };

        var repo = new FakeFoodRepository(localFood);
        var off = new FakeOffClient(null);
        var service = new FoodService(repo, off);

        var result = await service.GetByBarcodeAsync("123", default);

        result.Should().NotBeNull();
        result!.Name.Should().Be("Local Food");
        off.CallCount.Should().Be(0); // OFF non chiamato
    }

    [Fact]
    public async Task GetByBarcode_falls_back_to_off_when_not_in_db()
    {
        var offFood = new Food
        {
            Id = Guid.NewGuid(),
            Name = "OFF Food",
            Barcode = "456",
            Source = "openfoodfacts",
            Kcal = 150,
            ProteinG = 15,
            CarbsG = 25,
            FatG = 3
        };

        var repo = new FakeFoodRepository(null);
        var off = new FakeOffClient(offFood);
        var service = new FoodService(repo, off);

        var result = await service.GetByBarcodeAsync("456", default);

        result.Should().NotBeNull();
        result!.Name.Should().Be("OFF Food");
        off.CallCount.Should().Be(1);
        repo.LastUpserted.Should().NotBeNull();
    }

    private sealed class FakeFoodRepository : IFoodRepository
    {
        private readonly Food? _local;
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
        public int CallCount { get; private set; }

        public FakeOffClient(Food? food) => _food = food;

        public Task<Food?> GetProductByBarcodeAsync(string barcode, CancellationToken ct)
        {
            CallCount++;
            return Task.FromResult(_food);
        }
    }
}
