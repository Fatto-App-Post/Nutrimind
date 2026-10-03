namespace Nutrimind.Domain;

public class Food
{
    public Guid Id { get; set; }
    public string Name { get; set; } = "";
    public string? Brand { get; set; }
    public string? Barcode { get; set; }
    public string Source { get; set; } = "";
    public string SourceId { get; set; } = "";
    public string Verification { get; set; } = "";
    public decimal Kcal { get; set; }
    public decimal ProteinG { get; set; }
    public decimal CarbsG { get; set; }
    public decimal FatG { get; set; }
    public string? ImageFrontUrl { get; set; }
    public string? NutriscoreGrade { get; set; }
    public string? EcoscoreGrade { get; set; }
    public int? NovaGroup { get; set; }
}
