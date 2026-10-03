using System.Net;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc.Testing;
using FluentAssertions;

namespace Nutrimind.Tests.Integration;

public class OpenFoodFactsFallbackTests
{
    [Fact(Skip = "Requires Supabase configuration - run manually with secrets configured")]
    public async Task Barcode_endpoint_calls_off_when_not_in_db()
    {
        var factory = new WebApplicationFactory<Program>();
        var client = factory.CreateClient();

        var barcode = "9999999999999";
        var response = await client.GetAsync($"/api/foods/barcode/{barcode}");

        response.StatusCode.Should().BeOneOf(HttpStatusCode.NotFound, HttpStatusCode.OK);
    }

    [Fact(Skip = "Requires Supabase configuration - run manually with secrets configured")]
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
