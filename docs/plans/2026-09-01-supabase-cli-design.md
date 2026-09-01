# Supabase CLI Configuration Design

## Scope

Configure the existing repository for Supabase CLI use without creating or modifying any Swift source files.

## Local configuration

- Initialize the Supabase CLI in the repository, producing `supabase/config.toml`.
- Link the repository to project ref `gkgzwcxivnffsecshvfs`.
- Store the project URL, publishable key, and direct database URL in `.env.local`.
- Provide `.env.example` with safe placeholders so required variable names are documented.
- Ignore `.env.local` and Supabase's local working state so credentials and machine-specific files are not committed.

## Security

The database password is local-only. It must not appear in tracked documentation, examples, command output summaries, or committed configuration. The publishable client key is non-secret but is kept alongside the local environment settings for consistency.

## Verification

- Confirm the CLI configuration parses.
- Confirm the project is linked by running a read-only Supabase project command.
- Confirm secret-bearing files are ignored by Git.
- Confirm no Swift files are introduced.
