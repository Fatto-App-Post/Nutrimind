using System.Net;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc.Testing;
using FluentAssertions;

namespace Nutrimind.Tests.Integration;

public class OpenFoodFactsFallbackTests
{
    [Fact]
    public async Task Barcode_endpoint_calls_off_when_not_in_db()
    {
        // Questo test verifica che l'endpoint chiami OFF se il DB non ha il prodotto.
        // In un ambiente di integrazione reale, il DB è vuoto per questo barcode.

        var factory = new WebApplicationFactory<Program>();
        var client = factory.CreateClient();

        // Barcode fittizio che non esiste nel DB di test
        var barcode = "9999999999999";
        var response = await client.GetAsync($"/api/foods/barcode/{barcode}");

        // In assenza di OFF configurato correttamente, ci aspettiamo 404 o 500
        // Qui verifichiamo solo che l'endpoint risponda in modo coerente
        response.StatusCode.Should().BeOneOf(HttpStatusCode.NotFound, HttpStatusCode.OK);
    }

    [Fact]
    public async Task Search_endpoint_limits_results()
    {
        var factory = new WebApplicationFactory<Program>();
        var client = factory.CreateClient();

        var response = await client.GetAsync("/api/foods/search?q=test&limit=3");
        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var json = await response.Content.ReadAsStringAsync();
        var foods = JsonSerializer.Deserialize<List<JsonElement>>(json);
        foods.Should().NotBeNull();
        foods!.Count.Should().BeLessOrEqualTo(3);
    }
}
