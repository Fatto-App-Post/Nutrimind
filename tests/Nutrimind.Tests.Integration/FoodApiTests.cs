using System.Net;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc.Testing;
using FluentAssertions;

namespace Nutrimind.Tests.Integration;

public class FoodApiTests
{
    [Fact]
    public async Task Barcode_endpoint_returns_not_found_for_unknown()
    {
        var factory = new WebApplicationFactory<Program>();
        var client = factory.CreateClient();

        var response = await client.GetAsync("/api/foods/barcode/0000000000000");
        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Search_endpoint_requires_query_parameter()
    {
        var factory = new WebApplicationFactory<Program>();
        var client = factory.CreateClient();

        var response = await client.GetAsync("/api/foods/search");
        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Search_endpoint_returns_list()
    {
        var factory = new WebApplicationFactory<Program>();
        var client = factory.CreateClient();

        var response = await client.GetAsync("/api/foods/search?q=nutella&limit=5");
        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var json = await response.Content.ReadAsStringAsync();
        var foods = JsonSerializer.Deserialize<List<JsonElement>>(json);
        foods.Should().NotBeNull();
    }
}
