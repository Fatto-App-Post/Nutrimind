namespace Nutrimind.Domain;

public enum UserRole
{
    Patient = 0,
    Nutritionist = 1,
    Admin = 2
}

public enum LinkStatus
{
    Active = 0,
    Revoked = 1
}

public enum ConsentScope
{
    Adherence = 0,
    Diary = 1,
    Profile = 2
}

public enum VerificationStatus
{
    Pending = 0,
    Verified = 1,
    Rejected = 2
}

public record User(
    Guid Id,
    string Email,
    string DisplayName,
    UserRole Role,
    string Locale,
    bool ProfessionalVerified,
    DateTime CreatedAt
);

public record PatientSettings(
    Guid UserId,
    List<string> DietaryRestrictions,
    string Timezone,
    bool RemindersEnabled,
    int ReminderAfterHours,
    DateTime UpdatedAt
);

public record NutritionistDetails(
    Guid UserId,
    string? StudioName,
    string? Bio,
    DateTime UpdatedAt
);

public record ProfessionalVerification(
    Guid Id,
    Guid UserId,
    string LicenseBody,
    string LicenseNumber,
    VerificationStatus Status,
    Guid? ReviewedBy,
    DateTime? ReviewedAt,
    DateTime CreatedAt
);

public record PatientLink(
    Guid Id,
    Guid PatientId,
    Guid NutritionistId,
    LinkStatus Status,
    DateTime CreatedAt,
    DateTime? RevokedAt,
    Guid? RevokedBy
);

public record Consent(
    Guid Id,
    Guid LinkId,
    Guid PatientId,
    Guid NutritionistId,
    ConsentScope Scope,
    string PolicyVersion,
    DateTime GrantedAt,
    DateTime? RevokedAt
);

public record Invitation(
    Guid Id,
    Guid NutritionistId,
    string Code,
    DateTime ExpiresAt,
    Guid? UsedBy,
    DateTime? UsedAt,
    DateTime? RevokedAt,
    DateTime CreatedAt
);
