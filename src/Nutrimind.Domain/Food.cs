namespace Nutrimind.Domain;

public sealed class Food
{
    public Guid Id { get; init; }
    public string Name { get; init; } = "";
    public string? Brand { get; init; }
    public string? Barcode { get; init; }
    public string Source { get; init; } = "user";
    public string? SourceId { get; init; }
    public string Verification { get; init; } = "unverified";
    public decimal Kcal { get; init; }
    public decimal ProteinG { get; init; }
    public decimal CarbsG { get; init; }
    public decimal FatG { get; init; }
    public string? ImageFrontUrl { get; init; }
    public string? NutriscoreGrade { get; init; }
    public string? EcoscoreGrade { get; init; }
    public int? NovaGroup { get; init; }
}
