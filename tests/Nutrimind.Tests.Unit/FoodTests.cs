using Xunit;
using FluentAssertions;
using Nutrimind.Domain;

namespace Nutrimind.Tests.Unit;

public class FoodTests
{
    [Fact]
    public void Food_can_be_instantiated()
    {
        var food = new Food
        {
            Id = Guid.NewGuid(),
            Name = "Test",
            Kcal = 100,
            ProteinG = 10,
            CarbsG = 20,
            FatG = 5
        };

        food.Name.Should().Be("Test");
        food.Kcal.Should().Be(100);
    }
}
