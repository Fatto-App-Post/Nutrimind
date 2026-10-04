using Nutrimind.Domain;

namespace Nutrimind.Domain;

public interface IUserRepository
{
    Task<User?> GetByIdAsync(Guid id, CancellationToken ct = default);
    Task<User?> GetByEmailAsync(string email, CancellationToken ct = default);
    Task<User> CreateAsync(User user, string password, CancellationToken ct = default);
    Task<User> UpdateAsync(Guid id, User user, CancellationToken ct = default);
    Task<bool> DeleteAsync(Guid id, CancellationToken ct = default);
    
    Task<PatientSettings?> GetPatientSettingsAsync(Guid userId, CancellationToken ct = default);
    Task<PatientSettings> UpsertPatientSettingsAsync(PatientSettings settings, CancellationToken ct = default);
    
    Task<NutritionistDetails?> GetNutritionistDetailsAsync(Guid userId, CancellationToken ct = default);
    Task<NutritionistDetails> UpsertNutritionistDetailsAsync(NutritionistDetails details, CancellationToken ct = default);
    
    Task<ProfessionalVerification?> GetVerificationAsync(Guid userId, CancellationToken ct = default);
    Task<ProfessionalVerification> RequestVerificationAsync(ProfessionalVerification verification, CancellationToken ct = default);
    
    Task<string> CreateInvitationAsync(Guid nutritionistId, CancellationToken ct = default);
    Task<Guid?> RedeemInvitationAsync(string code, Guid patientId, ConsentScope[] scopes, string policyVersion, CancellationToken ct = default);
    Task<bool> RevokeLinkAsync(Guid linkId, Guid userId, CancellationToken ct = default);
    Task<bool> GrantConsentAsync(Guid linkId, Guid patientId, ConsentScope scope, string policyVersion, CancellationToken ct = default);
    Task<bool> RevokeConsentAsync(Guid linkId, Guid patientId, ConsentScope scope, CancellationToken ct = default);
}
