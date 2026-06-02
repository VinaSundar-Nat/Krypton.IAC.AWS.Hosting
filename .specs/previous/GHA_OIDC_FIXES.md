# GitHub Actions OIDC Authentication - Critical Fixes

## Issues Resolved

### 1. ✅ Hardcoded Account ID in Trust Policy (FIXED)
**Problem:** The trust policy had a hardcoded placeholder account ID `123456789012`, causing "Cannot assume IAM Role with web identity" error in the deploy job.

**Solution Applied:**
- Updated `create-gha-role.sh` to get the real account ID **before** creating the role
- Added `sed` substitution to replace `123456789012` with the real account ID when creating the role
- Trust policy now correctly references the actual AWS account OIDC provider

**Files Modified:**
- `.auth/create-gha-role.sh` - Account ID fetched first, policy substitution added

### 2. ✅ Flexible Subject Claims (FIXED)
**Problem:** Trust policy only allowed main branch, blocking feature branch deployments.

**Solution Applied:**
- Changed subject condition from `StringEquals` to `StringLike` 
- Now allows:
  - `repo:VinaSundar-Nat/Krypton.IAC.AWS.Hosting:ref:refs/heads/main`
  - `repo:VinaSundar-Nat/Krypton.IAC.AWS.Hosting:ref:refs/heads/feature/*`

**Files Modified:**
- `.auth/roles/role-gha-sts.json` - Updated subject claim conditions

---

## Required Manual Steps

### 3. ⚠️ GitHub Repository Settings Configuration (MANUAL)

The workflow requires GitHub **Environment Protection Rules** to be configured for approval gates. These must be set up in your GitHub repository settings:

#### Step-by-Step Instructions:

1. **Go to GitHub Repository Settings:**
   - Navigate to: `Settings` → `Environments`

2. **Create/Configure Environment: `dev-approval`**
   - Click `New environment` (or configure existing)
   - Name: `dev-approval`
   - Click `Configure environment`
   - Under "Deployment branches and tags":
     - Select: "Selected branches and tags"
     - Add pattern: `refs/heads/main` (and any other branches)
   - Under "Required reviewers":
     - ✅ Enable **"Require reviewers"**
     - Add at least one reviewer (repo owner or designated approver)
   - Click `Save protection rules`

3. **Repeat for `stage-approval` and `prod-approval`:**
   - Follow same process for:
     - `stage-approval` environment
     - `prod-approval` environment

4. **Verify Repository Secrets:**
   - `Settings` → `Secrets and variables` → `Actions`
   - Ensure secret `GHA_ROLE_ARN` exists (created by `.auth/create-gha-role.sh`)
   - Value should be: `arn:aws:iam::YOUR_ACCOUNT_ID:role/krypton-hosting-gha-exec`

---

## After Applying Fixes

### 1. Re-run the GHA Role Setup
Since the trust policy scripts have been fixed, re-create the IAM role (if it exists, the script will ask to use existing or skip):

```bash
cd .auth
./create-gha-role.sh --profile <your-aws-profile>
```

This will create the role with the **correct account ID** in the trust relationship.

### 2. Update GitHub Repository Settings (from Section 3 above)

### 3. Re-run the GitHub Actions Workflow
Once manual steps complete:
1. Navigate to `Actions` → `Hosting Plan & Deploy`
2. Click `Run workflow`
3. Select program and environment
4. Click `Run workflow`

#### Expected Flow:
- ✅ **Plan job** runs and completes successfully
- ✅ **Approval gate** blocks the deploy job (waiting for reviewer approval)
- ✅ Reviewers get notification to approve deployment
- ✅ After approval, **Deploy job** runs with authenticated OIDC token
- ✅ Terraform `apply` runs and succeeds

---

## Troubleshooting

### If Deploy Still Fails with Auth Error:

1. **Verify OIDC Provider is Registered:**
   ```bash
   aws iam list-open-id-connect-providers --profile <profile>
   # Should show: arn:aws:iam::ACCOUNT:oidc-provider/token.actions.githubusercontent.com
   ```

2. **Check Role's Trust Relationship:**
   ```bash
   aws iam get-role --role-name krypton-hosting-gha-exec --profile <profile>
   # Verify the AssumeRolePolicyDocument has the CORRECT account ID (not 123456789012)
   ```

3. **Verify Audience and Subject Claims:**
   - Audience must be: `sts.amazonaws.com` ✓ (already correct)
   - Subject must match GitHub context
   - Check workflow logs for actual OIDC token subject claim

4. **GitHub Token Permissions:**
   - Ensure workflow has `permissions: id-token: write` on both plan and deploy jobs ✓ (already correct)

---

## Architecture Summary

```
GitHub Actions Workflow
  ├─ Plan Job
  │   ├─ Checkout code
  │   ├─ Create OIDC token
  │   └─ Run terraform plan
  │
  ├─ ⛔ Approval Gate (blocking, requires reviewers)
  │
  └─ Deploy Job
      ├─ Checkout code
      ├─ Create fresh OIDC token (tokens are short-lived)
      ├─ Assume IAM Role via OIDC
      └─ Run terraform apply
```

**Key Point:** Each job gets a fresh OIDC token. Tokens are short-lived (15 min) and not shared between jobs.

---

## Files Changed in This Fix

| File | Change | Impact |
|------|--------|--------|
| `.auth/create-gha-role.sh` | Account ID fetched first, sed substitution added | Role created with correct account ID in trust policy |
| `.auth/roles/role-gha-sts.json` | Subject claim changed to StringLike with wildcards | Now supports feature branches and main branch |

---

## References
- [GitHub Actions OIDC Documentation](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [AWS AssumeRoleWithWebIdentity](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRoleWithWebIdentity.html)
- [Environment Protection Rules](https://docs.github.com/en/actions/deployment/using-environments-for-deployment#required-reviewers)
