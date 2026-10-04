using Nutrimind.Domain;
using Nutrimind.Infrastructure.Supabase;

namespace Nutrimind.Application;

public interface IUserService
{
    // Auth
    Task<RegisterResponse> RegisterAsync(RegisterRequest request, CancellationToken ct = default);
    Task<LoginResponse> LoginAsync(LoginRequest request, CancellationToken ct = default);
    Task LogoutAsync(CancellationToken ct = default);
    
    // Profile
    Task<UserResponse> GetProfileAsync(Guid userId, CancellationToken ct = default);
    Task<UserResponse> UpdateProfileAsync(Guid userId, UpdateProfileRequest request, CancellationToken ct = default);
    
    // Patient Settings
    Task<PatientSettingsResponse> GetPatientSettingsAsync(Guid userId, CancellationToken ct = default);
    Task<PatientSettingsResponse> UpdatePatientSettingsAsync(Guid userId, UpdatePatientSettingsRequest request, CancellationToken ct = default);
    
    // Nutritionist Details
    Task<NutritionistDetailsResponse> GetNutritionistDetailsAsync(Guid userId, CancellationToken ct = default);
    Task<NutritionistDetailsResponse> UpdateNutritionistDetailsAsync(Guid userId, UpdateNutritionistDetailsRequest request, CancellationToken ct = default);
    
    // Professional Verification
    Task<VerificationResponse?> GetVerificationAsync(Guid userId, CancellationToken ct = default);
    Task<VerificationResponse> RequestVerificationAsync(Guid userId, RequestVerificationRequest request, CancellationToken ct = default);
    
    // Invitations & Links
    Task<CreateInvitationResponse> CreateInvitationAsync(Guid nutritionistId, CancellationToken ct = default);
    Task<RedeemInvitationResponse> RedeemInvitationAsync(Guid patientId, RedeemInvitationRequest request, CancellationToken ct = default);
    Task<bool> RevokeLinkAsync(Guid linkId, Guid userId, CancellationToken ct = default);
    
    // Consents
    Task<bool> GrantConsentAsync(Guid userId, GrantConsentRequest request, CancellationToken ct = default);
    Task<bool> RevokeConsentAsync(Guid userId, RevokeConsentRequest request, CancellationToken ct = default);
}

public sealed class UserService : IUserService
{
    private readonly IUserRepository _repo;

    public UserService(IUserRepository repo)
    {
        _repo = repo;
    }

    public async Task<RegisterResponse> RegisterAsync(RegisterRequest request, CancellationToken ct = default)
    {
        var user = new User(
            Guid.NewGuid(),
            request.Email,
            request.DisplayName,
            request.Role,
            request.Locale ?? "it",
            false,
            DateTime.UtcNow
        );
        
        var created = await _repo.CreateAsync(user, request.Password, ct);
        
        return new RegisterResponse(
            new UserResponse(
                created.Id,
                created.Email,
                created.DisplayName,
                created.Role,
                created.Locale,
                created.ProfessionalVerified,
                created.CreatedAt
            )
        );
    }

    public async Task<LoginResponse> LoginAsync(LoginRequest request, CancellationToken ct = default)
    {
        var user = await _repo.GetByEmailAsync(request.Email, ct)
            ?? throw new InvalidOperationException("Invalid credentials");
        
        return new LoginResponse(
            new UserResponse(
                user.Id,
                user.Email,
                user.DisplayName,
                user.Role,
                user.Locale,
                user.ProfessionalVerified,
                user.CreatedAt
            ),
            new AuthTokens("access_token_placeholder", "refresh_token_placeholder")
        );
    }

    public Task LogoutAsync(CancellationToken ct = default)
    {
        return Task.CompletedTask;
    }

    public async Task<UserResponse> GetProfileAsync(Guid userId, CancellationToken ct = default)
    {
        var user = await _repo.GetByIdAsync(userId, ct)
            ?? throw new KeyNotFoundException($"User {userId} not found");
        
        return new UserResponse(
            user.Id,
            user.Email,
            user.DisplayName,
            user.Role,
            user.Locale,
            user.ProfessionalVerified,
            user.CreatedAt
        );
    }

    public async Task<UserResponse> UpdateProfileAsync(Guid userId, UpdateProfileRequest request, CancellationToken ct = default)
    {
        var user = await _repo.GetByIdAsync(userId, ct)
            ?? throw new KeyNotFoundException($"User {userId} not found");
        
        var updated = new User(
            user.Id,
            user.Email,
            request.DisplayName ?? user.DisplayName,
            user.Role,
            request.Locale ?? user.Locale,
            user.ProfessionalVerified,
            user.CreatedAt
        );
        
        var result = await _repo.UpdateAsync(userId, updated, ct);
        
        return new UserResponse(
            result.Id,
            result.Email,
            result.DisplayName,
            result.Role,
            result.Locale,
            result.ProfessionalVerified,
            result.CreatedAt
        );
    }

    public async Task<PatientSettingsResponse> GetPatientSettingsAsync(Guid userId, CancellationToken ct = default)
    {
        var settings = await _repo.GetPatientSettingsAsync(userId, ct)
            ?? throw new KeyNotFoundException($"Patient settings for user {userId} not found");
        
        return new PatientSettingsResponse(
            settings.DietaryRestrictions,
            settings.Timezone,
            settings.RemindersEnabled,
            settings.ReminderAfterHours
        );
    }

    public async Task<PatientSettingsResponse> UpdatePatientSettingsAsync(Guid userId, UpdatePatientSettingsRequest request, CancellationToken ct = default)
    {
        var current = await _repo.GetPatientSettingsAsync(userId, ct)
            ?? throw new KeyNotFoundException($"Patient settings for user {userId} not found");
        
        var updated = new PatientSettings(
            userId,
            request.DietaryRestrictions ?? current.DietaryRestrictions,
            request.Timezone ?? current.Timezone,
            request.RemindersEnabled ?? current.RemindersEnabled,
            request.ReminderAfterHours ?? current.ReminderAfterHours,
            current.UpdatedAt
        );
        
        var result = await _repo.UpsertPatientSettingsAsync(updated, ct);
        
        return new PatientSettingsResponse(
            result.DietaryRestrictions,
            result.Timezone,
            result.RemindersEnabled,
            result.ReminderAfterHours
        );
    }

    public async Task<NutritionistDetailsResponse> GetNutritionistDetailsAsync(Guid userId, CancellationToken ct = default)
    {
        var details = await _repo.GetNutritionistDetailsAsync(userId, ct)
            ?? throw new KeyNotFoundException($"Nutritionist details for user {userId} not found");
        
        return new NutritionistDetailsResponse(
            details.StudioName,
            details.Bio
        );
    }

    public async Task<NutritionistDetailsResponse> UpdateNutritionistDetailsAsync(Guid userId, UpdateNutritionistDetailsRequest request, CancellationToken ct = default)
    {
        var current = await _repo.GetNutritionistDetailsAsync(userId, ct)
            ?? throw new KeyNotFoundException($"Nutritionist details for user {userId} not found");
        
        var updated = new NutritionistDetails(
            userId,
            request.StudioName ?? current.StudioName,
            request.Bio ?? current.Bio,
            current.UpdatedAt
        );
        
        var result = await _repo.UpsertNutritionistDetailsAsync(updated, ct);
        
        return new NutritionistDetailsResponse(
            result.StudioName,
            result.Bio
        );
    }

    public async Task<VerificationResponse?> GetVerificationAsync(Guid userId, CancellationToken ct = default)
    {
        var verification = await _repo.GetVerificationAsync(userId, ct);
        
        if (verification is null) return null;
        
        return new VerificationResponse(
            verification.Id,
            verification.LicenseBody,
            verification.LicenseNumber,
            verification.Status,
            verification.ReviewedAt,
            verification.CreatedAt
        );
    }

    public async Task<VerificationResponse> RequestVerificationAsync(Guid userId, RequestVerificationRequest request, CancellationToken ct = default)
    {
        var verification = new ProfessionalVerification(
            Guid.NewGuid(),
            userId,
            request.LicenseBody,
            request.LicenseNumber,
            VerificationStatus.Pending,
            null,
            null,
            DateTime.UtcNow
        );
        
        var result = await _repo.RequestVerificationAsync(verification, ct);
        
        return new VerificationResponse(
            result.Id,
            result.LicenseBody,
            result.LicenseNumber,
            result.Status,
            result.ReviewedAt,
            result.CreatedAt
        );
    }

    public async Task<CreateInvitationResponse> CreateInvitationAsync(Guid nutritionistId, CancellationToken ct = default)
    {
        var code = await _repo.CreateInvitationAsync(nutritionistId, ct);
        
        return new CreateInvitationResponse(
            code,
            DateTime.UtcNow.AddDays(7)
        );
    }

    public async Task<RedeemInvitationResponse> RedeemInvitationAsync(Guid patientId, RedeemInvitationRequest request, CancellationToken ct = default)
    {
        var linkId = await _repo.RedeemInvitationAsync(
            request.Code,
            patientId,
            request.Scopes ?? Array.Empty<ConsentScope>(),
            request.PolicyVersion ?? "1.0",
            ct
        ) ?? throw new InvalidOperationException("Invalid or expired invitation code");
        
        var nutritionistId = Guid.NewGuid();
        
        return new RedeemInvitationResponse(
            linkId,
            nutritionistId
        );
    }

    public async Task<bool> RevokeLinkAsync(Guid linkId, Guid userId, CancellationToken ct = default)
    {
        return await _repo.RevokeLinkAsync(linkId, userId, ct);
    }

    public async Task<bool> GrantConsentAsync(Guid userId, GrantConsentRequest request, CancellationToken ct = default)
    {
        return await _repo.GrantConsentAsync(request.LinkId, userId, request.Scope, request.PolicyVersion, ct);
    }

    public async Task<bool> RevokeConsentAsync(Guid userId, RevokeConsentRequest request, CancellationToken ct = default)
    {
        return await _repo.RevokeConsentAsync(request.LinkId, userId, request.Scope, ct);
    }
}
