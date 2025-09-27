# GitHub Repository Secrets Setup for pub.dev Publishing

This document explains how to configure the required GitHub repository secrets for automated pub.dev publishing.

## Required Secrets

The publishing workflows require two secrets to be configured in the GitHub repository:

- `PUB_TOKEN` - Your pub.dev access token
- `PUB_REFRESH_TOKEN` - Your pub.dev refresh token

## Obtaining pub.dev Credentials

### Step 1: Generate Credentials Locally

Run the following command on your local machine:

```bash
dart pub token add https://pub.dev
```

This will:
1. Open your web browser
2. Prompt you to sign in to pub.dev with your Google account
3. Grant permission for Dart to publish packages on your behalf
4. Store credentials locally

### Step 2: Extract Credentials

Find your credentials file at:
- **Linux/macOS**: `~/.config/dart/pub-credentials.json`
- **Windows**: `%APPDATA%\dart\pub-credentials.json`

Open the file and extract the following values:
```json
{
  "accessToken": "ya29.XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
  "refreshToken": "1//XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
  "tokenEndpoint": "https://accounts.google.com/o/oauth2/token",
  "scopes": ["openid", "https://www.googleapis.com/auth/userinfo.email"],
  "expiration": 4070908800000
}
```

Copy the `accessToken` and `refreshToken` values (without quotes).

## Configuring GitHub Repository Secrets

### Step 1: Navigate to Repository Settings

1. Go to the GitHub repository: https://github.com/graknol/declarative_sqlite
2. Click on the **Settings** tab
3. In the left sidebar, click on **Secrets and variables** → **Actions**

### Step 2: Add Secrets

Click **New repository secret** for each of the following:

#### Secret 1: PUB_TOKEN
- **Name**: `PUB_TOKEN`
- **Value**: Paste the `accessToken` value from your credentials file
- Click **Add secret**

#### Secret 2: PUB_REFRESH_TOKEN
- **Name**: `PUB_REFRESH_TOKEN`
- **Value**: Paste the `refreshToken` value from your credentials file
- Click **Add secret**

## Security Considerations

- ⚠️ **Never commit credentials to source code**
- ⚠️ **Do not share these tokens with unauthorized users**
- ⚠️ **These tokens provide full publishing access to your pub.dev account**
- ✅ **GitHub repository secrets are encrypted and only accessible to workflows**
- ✅ **Consider using a dedicated pub.dev account for automated publishing if preferred**

## Verification

After configuring the secrets, you can test the setup by:

1. **Manual Workflow Test**: 
   - Go to Actions tab → "Test Publishing Workflows"
   - Click "Run workflow" and test with dry-run enabled

2. **Tag-based Test**:
   ```bash
   # Create a test tag (don't use a real version)
   git tag declarative_sqlite-test-1.0.0
   git push origin declarative_sqlite-test-1.0.0
   
   # Monitor Actions tab for workflow execution
   # Delete the test tag afterwards:
   git tag -d declarative_sqlite-test-1.0.0
   git push origin --delete declarative_sqlite-test-1.0.0
   ```

## Troubleshooting

### "Invalid credentials" Error
- Verify the tokens were copied correctly (no extra spaces/characters)
- Regenerate credentials if they've expired
- Ensure the account has publishing permissions

### "Package not found" Error  
- Verify the package name matches exactly
- Ensure the account has permission to publish to the package
- Check if this is the first publication (may need manual first publish)

### Workflow Permission Errors
- Ensure repository Actions are enabled
- Check that secrets are spelled correctly (case-sensitive)
- Verify workflow files are on the main branch

## Credential Rotation

For security, consider rotating credentials periodically:

1. Generate new credentials: `dart pub token add https://pub.dev`
2. Update GitHub repository secrets with new values
3. Test with a dry-run workflow
4. The old credentials will be automatically invalidated

## Support

If you encounter issues:

1. Check the GitHub Actions logs for detailed error messages
2. Verify secrets are configured correctly
3. Test credential validity locally: `dart pub publish --dry-run`
4. Consult the [pub.dev publishing documentation](https://dart.dev/tools/pub/publishing)

Remember: These credentials are powerful - treat them with the same security as you would your personal Google account password.