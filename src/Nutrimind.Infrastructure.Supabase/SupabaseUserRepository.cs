using Nutrimind.Domain;
using Supabase;
using Postgrest.Models;
using Postgrest.Attributes;
using Postgrest.Responses;

namespace Nutrimind.Infrastructure.Supabase;

public sealed class SupabaseUserRepository : IUserRepository
{
    private readonly Client _client;

    public SupabaseUserRepository(Client client)
    {
        _client = client;
    }

    public async Task<User?> GetByIdAsync(Guid id, CancellationToken ct = default)
    {
        var response = await _client.From<ProfileEntity>().Where(x => x.Id == id).Single();
        if (response is null) return null;
        
        return new User(
            response.Id,
            response.Email ?? "",
            response.DisplayName,
            (UserRole)Enum.Parse(typeof(UserRole), response.Role, true),
            response.Locale,
            response.ProfessionalVerified,
            response.CreatedAt
        );
    }

    public async Task<User?> GetByEmailAsync(string email, CancellationToken ct = default)
    {
        var response = await _client.From<ProfileEntity>().Where(x => x.Email == email).Single();
        if (response is null) return null;
        
        return new User(
            response.Id,
            response.Email ?? "",
            response.DisplayName,
            (UserRole)Enum.Parse(typeof(UserRole), response.Role, true),
            response.Locale,
            response.ProfessionalVerified,
            response.CreatedAt
        );
    }

    public Task<User> CreateAsync(User user, string password, CancellationToken ct = default)
    {
        throw new NotImplementedException("User creation must be done via Supabase Auth API");
    }

    public async Task<User> UpdateAsync(Guid id, User user, CancellationToken ct = default)
    {
        var entity = new ProfileEntity
        {
            Id = id,
            DisplayName = user.DisplayName,
            Locale = user.Locale
        };
        
        var response = await _client.From<ProfileEntity>().Where(x => x.Id == id).Update(entity);
        var model = response.Models.First();
        
        return new User(
            model.Id,
            model.Email ?? "",
            model.DisplayName,
            (UserRole)Enum.Parse(typeof(UserRole), model.Role, true),
            model.Locale,
            model.ProfessionalVerified,
            model.CreatedAt
        );
    }

    public async Task<bool> DeleteAsync(Guid id, CancellationToken ct = default)
    {
        await _client.From<ProfileEntity>().Where(x => x.Id == id).Delete();
        return true;
    }

    public async Task<PatientSettings?> GetPatientSettingsAsync(Guid userId, CancellationToken ct = default)
    {
        var response = await _client.From<PatientSettingsEntity>().Where(x => x.UserId == userId).Single();
        if (response is null) return null;
        
        return new PatientSettings(
            response.UserId,
            response.DietaryRestrictions?.ToList() ?? new List<string>(),
            response.Timezone,
            response.RemindersEnabled,
            response.ReminderAfterHours,
            response.UpdatedAt
        );
    }

    public async Task<PatientSettings> UpsertPatientSettingsAsync(PatientSettings settings, CancellationToken ct = default)
    {
        var entity = new PatientSettingsEntity
        {
            UserId = settings.UserId,
            DietaryRestrictions = settings.DietaryRestrictions.ToArray(),
            Timezone = settings.Timezone,
            RemindersEnabled = settings.RemindersEnabled,
            ReminderAfterHours = (short)settings.ReminderAfterHours
        };
        
        var response = await _client.From<PatientSettingsEntity>().Where(x => x.UserId == settings.UserId).Upsert(entity);
        var model = response.Models.First();
        
        return new PatientSettings(
            model.UserId,
            model.DietaryRestrictions?.ToList() ?? new List<string>(),
            model.Timezone,
            model.RemindersEnabled,
            model.ReminderAfterHours,
            model.UpdatedAt
        );
    }

    public async Task<NutritionistDetails?> GetNutritionistDetailsAsync(Guid userId, CancellationToken ct = default)
    {
        var response = await _client.From<NutritionistDetailsEntity>().Where(x => x.UserId == userId).Single();
        if (response is null) return null;
        
        return new NutritionistDetails(
            response.UserId,
            response.StudioName,
            response.Bio,
            response.UpdatedAt
        );
    }

    public async Task<NutritionistDetails> UpsertNutritionistDetailsAsync(NutritionistDetails details, CancellationToken ct = default)
    {
        var entity = new NutritionistDetailsEntity
        {
            UserId = details.UserId,
            StudioName = details.StudioName,
            Bio = details.Bio
        };
        
        var response = await _client.From<NutritionistDetailsEntity>().Where(x => x.UserId == details.UserId).Upsert(entity);
        var model = response.Models.First();
        
        return new NutritionistDetails(
            model.UserId,
            model.StudioName,
            model.Bio,
            model.UpdatedAt
        );
    }

    public async Task<ProfessionalVerification?> GetVerificationAsync(Guid userId, CancellationToken ct = default)
    {
        var response = await _client.From<ProfessionalVerificationEntity>()
            .Where(x => x.UserId == userId)
            .Limit(1)
            .Get();
        
        var model = response.Models.FirstOrDefault();
        if (model is null) return null;
        
        return new ProfessionalVerification(
            model.Id,
            model.UserId,
            model.LicenseBody,
            model.LicenseNumber,
            (VerificationStatus)Enum.Parse(typeof(VerificationStatus), model.Status, true),
            model.ReviewedBy,
            model.ReviewedAt,
            model.CreatedAt
        );
    }

    public async Task<ProfessionalVerification> RequestVerificationAsync(ProfessionalVerification verification, CancellationToken ct = default)
    {
        var entity = new ProfessionalVerificationEntity
        {
            UserId = verification.UserId,
            LicenseBody = verification.LicenseBody,
            LicenseNumber = verification.LicenseNumber,
            Status = "pending"
        };
        
        var response = await _client.From<ProfessionalVerificationEntity>().Insert(new[] { entity });
        var model = response.Models.First();
        
        return new ProfessionalVerification(
            model.Id,
            model.UserId,
            model.LicenseBody,
            model.LicenseNumber,
            (VerificationStatus)Enum.Parse(typeof(VerificationStatus), model.Status, true),
            model.ReviewedBy,
            model.ReviewedAt,
            model.CreatedAt
        );
    }

    public async Task<string> CreateInvitationAsync(Guid nutritionistId, CancellationToken ct = default)
    {
        var response = await _client.Rpc("create_invitation", new Dictionary<string, object>());
        return response?.ToString() ?? throw new InvalidOperationException("Failed to create invitation");
    }

    public async Task<Guid?> RedeemInvitationAsync(string code, Guid patientId, ConsentScope[] scopes, string policyVersion, CancellationToken ct = default)
    {
        var result = await _client.Rpc("redeem_invitation", new Dictionary<string, object>
        {
            ["p_code"] = code,
            ["p_scopes"] = scopes.Select(s => s.ToString().ToLower()).ToArray(),
            ["p_policy_version"] = policyVersion
        });
        
        return result != null ? Guid.Parse(result.ToString()!) : null;
    }

    public async Task<bool> RevokeLinkAsync(Guid linkId, Guid userId, CancellationToken ct = default)
    {
        await _client.Rpc("revoke_link", new Dictionary<string, object> { ["p_link_id"] = linkId });
        return true;
    }

    public async Task<bool> GrantConsentAsync(Guid linkId, Guid patientId, ConsentScope scope, string policyVersion, CancellationToken ct = default)
    {
        await _client.Rpc("grant_consent", new Dictionary<string, object>
        {
            ["p_link_id"] = linkId,
            ["p_scope"] = scope.ToString().ToLower(),
            ["p_policy_version"] = policyVersion
        });
        return true;
    }

    public async Task<bool> RevokeConsentAsync(Guid linkId, Guid patientId, ConsentScope scope, CancellationToken ct = default)
    {
        await _client.Rpc("revoke_consent", new Dictionary<string, object>
        {
            ["p_link_id"] = linkId,
            ["p_scope"] = scope.ToString().ToLower()
        });
        return true;
    }
}

[Table("profiles")]
public class ProfileEntity : BaseModel
{
    [PrimaryKey("id", false)]
    public Guid Id { get; set; }

    [Column("email")]
    public string? Email { get; set; }

    [Column("role")]
    public string Role { get; set; } = "patient";

    [Column("display_name")]
    public string DisplayName { get; set; } = "";

    [Column("locale")]
    public string Locale { get; set; } = "it";

    [Column("professional_verified")]
    public bool ProfessionalVerified { get; set; }

    [Column("created_at")]
    public DateTime CreatedAt { get; set; }
}

[Table("patient_settings")]
public class PatientSettingsEntity : BaseModel
{
    [PrimaryKey("user_id", false)]
    public Guid UserId { get; set; }

    [Column("dietary_restrictions")]
    public string[]? DietaryRestrictions { get; set; }

    [Column("timezone")]
    public string Timezone { get; set; } = "Europe/Rome";

    [Column("reminders_enabled")]
    public bool RemindersEnabled { get; set; } = true;

    [Column("reminder_after_hours")]
    public short ReminderAfterHours { get; set; } = 24;

    [Column("updated_at")]
    public DateTime UpdatedAt { get; set; }
}

[Table("nutritionist_details")]
public class NutritionistDetailsEntity : BaseModel
{
    [PrimaryKey("user_id", false)]
    public Guid UserId { get; set; }

    [Column("studio_name")]
    public string? StudioName { get; set; }

    [Column("bio")]
    public string? Bio { get; set; }

    [Column("updated_at")]
    public DateTime UpdatedAt { get; set; }
}

[Table("professional_verifications")]
public class ProfessionalVerificationEntity : BaseModel
{
    [PrimaryKey("id", false)]
    public Guid Id { get; set; }

    [Column("user_id")]
    public Guid UserId { get; set; }

    [Column("license_body")]
    public string LicenseBody { get; set; } = "";

    [Column("license_number")]
    public string LicenseNumber { get; set; } = "";

    [Column("status")]
    public string Status { get; set; } = "pending";

    [Column("reviewed_by")]
    public Guid? ReviewedBy { get; set; }

    [Column("reviewed_at")]
    public DateTime? ReviewedAt { get; set; }

    [Column("created_at")]
    public DateTime CreatedAt { get; set; }
}
