using FluentAssertions;
using System.Text.Json;
using Nutrimind.Infrastructure.OpenFoodFacts;

namespace Nutrimind.Tests.Unit;

public class OpenFoodFactsClientTests
{
    [Fact]
    public async Task GetProductByBarcode_maps_known_product()
    {
        // JSON semplificato di un prodotto OFF reale (es. Nutella)
        var json = """
        {
          "code": "3017620422003",
          "product": {
            "product_name": "Nutella",
            "product_name_it": "Nutella",
            "brands": "Ferrero",
            "nutriscore_grade": "e",
            "nova_group": 4,
            "nutriments": {
              "energy-kcal_100g": 539,
              "proteins_100g": 6.3,
              "carbohydrates_100g": 57.5,
              "fat_100g": 30.9
            }
          },
          "status": 1
        }
        """;

        var handler = new MockHttpMessageHandler(json);
        using var http = new HttpClient(handler) { BaseAddress = new Uri("https://world.openfoodfacts.net") };
        var client = new OpenFoodFactsClient(http);

        var food = await client.GetProductByBarcodeAsync("3017620422003", default);

        food.Should().NotBeNull();
        food!.Name.Should().Be("Nutella");
        food.Brand.Should().Be("Ferrero");
        food.Kcal.Should().Be(539);
        food.ProteinG.Should().Be(6.3m);
        food.CarbsG.Should().Be(57.5m);
        food.FatG.Should().Be(30.9m);
        food.NutriscoreGrade.Should().Be("e");
        food.NovaGroup.Should().Be(4);
    }

    [Fact]
    public async Task GetProductByBarcode_returns_null_when_status_zero()
    {
        var json = """
        {
          "code": "0000000000000",
          "status": 0
        }
        """;

        var handler = new MockHttpMessageHandler(json);
        using var http = new HttpClient(handler) { BaseAddress = new Uri("https://world.openfoodfacts.net") };
        var client = new OpenFoodFactsClient(http);

        var food = await client.GetProductByBarcodeAsync("0000000000000", default);

        food.Should().BeNull();
    }

    private sealed class MockHttpMessageHandler : HttpMessageHandler
    {
        private readonly string _response;

        public MockHttpMessageHandler(string response) => _response = response;

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            var response = new HttpResponseMessage(System.Net.HttpStatusCode.OK)
            {
                Content = new StringContent(_response, System.Text.Encoding.UTF8, "application/json")
            };
            return Task.FromResult(response);
        }
    }
}
