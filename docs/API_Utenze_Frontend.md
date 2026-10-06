# NutriMind API - Documentazione per Frontend

## Autenticazione e Gestione Utenze

Questa documentazione descrive le API per la gestione dell'autenticazione e delle utenze, da integrare nella parte di login e registrazione del frontend.

---

## 1. Registrazione

### Endpoint
```
POST /api/auth/register
```

### Request Body
```json
{
  "email": "mario.rossi@email.com",
  "password": "PasswordSicura123!",
  "displayName": "Mario Rossi",
  "role": "patient",
  "locale": "it"
}
```

**Campi:**
- `email` (string, required): Email dell'utente
- `password` (string, required): Password (min 8 caratteri)
- `displayName` (string, required): Nome visualizzato
- `role` (enum, required): `"patient"` o `"nutritionist"`
- `locale` (string, optional): Lingua, default `"it"`

### Response (200 OK)
```json
{
  "user": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "email": "mario.rossi@email.com",
    "displayName": "Mario Rossi",
    "role": "patient",
    "locale": "it",
    "professionalVerified": false,
    "createdAt": "2026-10-04T12:00:00Z"
  }
}
```

### Errori
- `400 Bad Request`: Email già esistente o password non valida
- `422 Unprocessable Entity`: Dati non validi

---

## 2. Login

### Endpoint
```
POST /api/auth/login
```

### Request Body
```json
{
  "email": "mario.rossi@email.com",
  "password": "PasswordSicura123!"
}
```

### Response (200 OK)
```json
{
  "user": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "email": "mario.rossi@email.com",
    "displayName": "Mario Rossi",
    "role": "patient",
    "locale": "it",
    "professionalVerified": false,
    "createdAt": "2026-10-04T12:00:00Z"
  },
  "tokens": {
    "accessToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "refreshToken": "dGhpcyBpcyBhIHJlZnJlc2ggdG9rZW4..."
  }
}
```

### Errori
- `401 Unauthorized`: Email o password non validi

---

## 3. Logout

### Endpoint
```
POST /api/auth/logout
```

### Headers
```
Authorization: Bearer {accessToken}
```

### Response (200 OK)
```json
{}
```

---

## 4. Ottieni Profilo Corrente

### Endpoint
```
GET /api/users/me
```

### Headers
```
Authorization: Bearer {accessToken}
```

### Response (200 OK)
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "email": "mario.rossi@email.com",
  "displayName": "Mario Rossi",
  "role": "patient",
  "locale": "it",
  "professionalVerified": false,
  "createdAt": "2026-10-04T12:00:00Z"
}
```

---

## 5. Aggiorna Profilo

### Endpoint
```
PUT /api/users/me
```

### Headers
```
Authorization: Bearer {accessToken}
```

### Request Body
```json
{
  "displayName": "Mario Rossi Updated",
  "locale": "en"
}
```

**Campi:**
- `displayName` (string, optional): Nuovo nome visualizzato
- `locale` (string, optional): Nuova lingua

### Response (200 OK)
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "email": "mario.rossi@email.com",
  "displayName": "Mario Rossi Updated",
  "role": "patient",
  "locale": "en",
  "professionalVerified": false,
  "createdAt": "2026-10-04T12:00:00Z"
}
```

---

## 6. Impostazioni Paziente

### Endpoint
```
GET /api/users/me/patient-settings
```

### Response (200 OK)
```json
{
  "dietaryRestrictions": ["vegetarian", "gluten_free"],
  "timezone": "Europe/Rome",
  "remindersEnabled": true,
  "reminderAfterHours": 24
}
```

**Valori ammissibili per `dietaryRestrictions`:**
- `vegetarian`
- `vegan`
- `gluten_free`
- `lactose_free`
- `nut_free`
- `halal`
- `kosher`
- `no_pork`
- `no_fish`

---

### Aggiorna Impostazioni Paziente
```
PUT /api/users/me/patient-settings
```

**Request Body:**
```json
{
  "dietaryRestrictions": ["vegan", "gluten_free"],
  "timezone": "Europe/London",
  "remindersEnabled": false,
  "reminderAfterHours": 48
}
```

---

## 7. Dettagli Nutrizionista

### Endpoint
```
GET /api/users/me/nutritionist-details
```

### Response (200 OK)
```json
{
  "studioName": "Studio Nutrizionale Rossi",
  "bio": "Nutrizionista specializzato in..."
}
```

---

### Aggiorna Dettagli Nutrizionista
```
PUT /api/users/me/nutritionist-details
```

**Request Body:**
```json
{
  "studioName": "Nuovo Studio",
  "bio": "Nuova biografia..."
}
```

---

## 8. Verifica Professionale (solo Nutrizionisti)

### Richiedi Verifica
```
POST /api/users/me/verification
```

**Request Body:**
```json
{
  "licenseBody": "Ordine dei Biologi del Lazio",
  "licenseNumber": "12345"
}
```

**Response (200 OK):**
```json
{
  "id": "uuid-verifica",
  "licenseBody": "Ordine dei Biologi del Lazio",
  "licenseNumber": "12345",
  "status": "pending",
  "reviewedAt": null,
  "createdAt": "2026-10-04T12:00:00Z"
}
```

**Stati possibili:**
- `pending`: In attesa di revisione
- `verified`: Verificato
- `rejected`: Rifiutato

---

### Ottieni Stato Verifica
```
GET /api/users/me/verification
```

**Response (200 OK):**
```json
{
  "id": "uuid-verifica",
  "licenseBody": "Ordine dei Biologi del Lazio",
  "licenseNumber": "12345",
  "status": "verified",
  "reviewedAt": "2026-10-05T10:00:00Z",
  "createdAt": "2026-10-04T12:00:00Z"
}
```

---

## 9. Collegamento Paziente-Nutrizionista

### Crea Invito (solo Nutrizionisti)
```
POST /api/users/invitations
```

**Response (200 OK):**
```json
{
  "code": "ABC123XYZ9",
  "expiresAt": "2026-10-11T12:00:00Z"
}
```

Il codice è valido per 7 giorni.

---

### Riscatta Invito (solo Pazienti)
```
POST /api/users/invitations/redeem
```

**Request Body:**
```json
{
  "code": "ABC123XYZ9",
  "scopes": ["adherence", "diary"],
  "policyVersion": "1.0"
}
```

**Scopi disponibili:**
- `adherence`: Aderenza al piano (dati aggregati)
- `diary`: Dettaglio diario alimentare (include adherence)
- `profile`: Restrizioni alimentari

**Response (200 OK):**
```json
{
  "linkId": "uuid-link",
  "nutritionistId": "uuid-nutrizionista"
}
```

---

### Interrompi Collegamento
```
DELETE /api/users/links/{linkId}
```

**Response (200 OK):**
```json
{}
```

---

## 10. Consensi (GDPR)

### Concedi Consenso (solo Pazienti)
```
POST /api/users/consents
```

**Request Body:**
```json
{
  "linkId": "uuid-link",
  "scope": "diary",
  "policyVersion": "1.0"
}
```

**Response (200 OK):**
```json
{}
```

---

### Revoca Consenso (solo Pazienti)
```
DELETE /api/users/consents
```

**Request Body:**
```json
{
  "linkId": "uuid-link",
  "scope": "diary"
}
```

**Response (200 OK):**
```json
{}
```

---

## Errori Comuni

### 400 Bad Request
```json
{
  "error": "invalid_email",
  "message": "Email format non valido"
}
```

### 401 Unauthorized
```json
{
  "error": "unauthorized",
  "message": "Token non valido o scaduto"
}
```

### 403 Forbidden
```json
{
  "error": "forbidden",
  "message": "Operazione non consentita per il ruolo utente"
}
```

### 404 Not Found
```json
{
  "error": "not_found",
  "message": "Risorsa non trovata"
}
```

### 422 Unprocessable Entity
```json
{
  "error": "validation_error",
  "message": "Dati non validi",
  "details": [
    {
      "field": "email",
      "message": "Email già registrata"
    }
  ]
}
```

---

## Note per il Frontend

1. **Token Management**: I token vanno salvati in modo sicuro (es. httpOnly cookies o secure storage) e inclusi in ogni richiesta con header `Authorization: Bearer {token}`

2. **Refresh Token**: Implementare il refresh automatico del token quando scaduto

3. **Ruoli**: Il frontend deve gestire UI diverse per `patient` vs `nutritionist`

4. **Verifica Nutrizionisti**: I nutrizionisti non verificati non possono approvare pasti o alimenti

5. **Consenso GDPR**: Il paziente deve esplicitamente concedere i consensi al nutrizionista

6. **Inviti**: Solo i nutrizionisti possono creare codici invito, solo i pazienti possono riscattarli

---

## Esempio Flusso Completo

### 1. Registrazione Paziente
```javascript
POST /api/auth/register
{
  "email": "paziente@email.com",
  "password": "Password123!",
  "displayName": "Mario Paziente",
  "role": "patient"
}
```

### 2. Login
```javascript
POST /api/auth/login
{
  "email": "paziente@email.com",
  "password": "Password123!"
}
// Salva tokens
```

### 3. Nutrizionista crea invito
```javascript
POST /api/users/invitations
// Response: { "code": "ABC123XYZ9", "expiresAt": "..." }
```

### 4. Paziente riscatta invito
```javascript
POST /api/users/invitations/redeem
{
  "code": "ABC123XYZ9",
  "scopes": ["adherence", "diary"],
  "policyVersion": "1.0"
}
```

### 5. Paziente concede consensi
```javascript
POST /api/users/consents
{
  "linkId": "uuid-link",
  "scope": "diary",
  "policyVersion": "1.0"
}
```

Ora il nutrizionista può vedere il diario del paziente!
