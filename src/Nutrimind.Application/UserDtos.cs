using Nutrimind.Domain;

namespace Nutrimind.Application;

// ==================== REQUEST DTOs ====================

public record RegisterRequest(
    string Email,
    string Password,
    string DisplayName,
    UserRole Role,
    string? Locale = "it"
);

public record LoginRequest(
    string Email,
    string Password
);

public record UpdateProfileRequest(
    string? DisplayName = null,
    string? Locale = null
);

public record UpdatePatientSettingsRequest(
    List<string>? DietaryRestrictions = null,
    string? Timezone = null,
    bool? RemindersEnabled = null,
    int? ReminderAfterHours = null
);

public record UpdateNutritionistDetailsRequest(
    string? StudioName = null,
    string? Bio = null
);

public record RequestVerificationRequest(
    string LicenseBody,
    string LicenseNumber
);

public record RedeemInvitationRequest(
    string Code,
    ConsentScope[]? Scopes = null,
    string? PolicyVersion = null
);

public record GrantConsentRequest(
    Guid LinkId,
    ConsentScope Scope,
    string PolicyVersion
);

public record RevokeConsentRequest(
    Guid LinkId,
    ConsentScope Scope
);

// ==================== RESPONSE DTOs ====================

public record UserResponse(
    Guid Id,
    string Email,
    string DisplayName,
    UserRole Role,
    string Locale,
    bool ProfessionalVerified,
    DateTime CreatedAt
);

public record PatientSettingsResponse(
    List<string> DietaryRestrictions,
    string Timezone,
    bool RemindersEnabled,
    int ReminderAfterHours
);

public record NutritionistDetailsResponse(
    string? StudioName,
    string? Bio
);

public record VerificationResponse(
    Guid Id,
    string LicenseBody,
    string LicenseNumber,
    VerificationStatus Status,
    DateTime? ReviewedAt,
    DateTime CreatedAt
);

public record CreateInvitationResponse(
    string Code,
    DateTime ExpiresAt
);

public record RedeemInvitationResponse(
    Guid LinkId,
    Guid NutritionistId
);

public record PatientLinkResponse(
    Guid Id,
    Guid PatientId,
    Guid NutritionistId,
    LinkStatus Status,
    DateTime CreatedAt
);

public record ConsentResponse(
    Guid Id,
    Guid LinkId,
    ConsentScope Scope,
    string PolicyVersion,
    DateTime GrantedAt,
    bool IsActive
);

public record AuthTokens(
    string AccessToken,
    string? RefreshToken
);

public record LoginResponse(
    UserResponse User,
    AuthTokens Tokens
);

public record RegisterResponse(
    UserResponse User
);
