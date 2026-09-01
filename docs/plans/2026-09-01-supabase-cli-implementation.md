# Supabase CLI Configuration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Configure this repository for safe local Supabase CLI access to project `gkgzwcxivnffsecshvfs` without adding Swift files.

**Architecture:** Supabase CLI owns `supabase/config.toml` and the local project link. Repository-local environment files expose consistent variable names while `.gitignore` prevents the password-bearing file and CLI working state from entering version control.

**Tech Stack:** Supabase CLI 2.75.0, dotenv files, Git ignore rules

---

### Task 1: Add environment-file safety rules

**Files:**
- Create: `.gitignore`

**Step 1: Verify the secret file is not currently ignored**

Run: `git check-ignore -q .env.local`
Expected: non-zero exit status because the rule does not exist yet.

**Step 2: Add minimal ignore rules**

Ignore `.env.local`, common Supabase local state, and CLI branch state while leaving `.env.example` trackable.

**Step 3: Verify the rule**

Run: `git check-ignore -v .env.local`
Expected: output points to `.gitignore`.

### Task 2: Add local and example environment files

**Files:**
- Create: `.env.local`
- Create: `.env.example`

**Step 1: Document required variables safely**

Create `.env.example` with `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, and `SUPABASE_DB_URL`; use a password placeholder in the connection URL.

**Step 2: Add local values**

Create `.env.local` with the supplied URL, publishable key, and percent-encoded direct PostgreSQL connection URL.

**Step 3: Verify secret isolation without printing values**

Run checks that confirm all three variable names exist and `.env.local` is ignored; never print the file contents.

### Task 3: Initialize and link Supabase CLI

**Files:**
- Create: `supabase/config.toml`
- Create locally: `supabase/.temp/project-ref`

**Step 1: Initialize the repository**

Run: `supabase init`
Expected: `supabase/config.toml` is created.

**Step 2: Confirm CLI authentication**

Run: `supabase projects list`
Expected: authenticated project list, or an authentication prompt if login is required.

**Step 3: Link the project**

Run: `supabase link --project-ref gkgzwcxivnffsecshvfs --password <local database password>`
Expected: the local project reference is set. The password must not be logged or written to tracked files.

### Task 4: Verify the complete configuration

**Files:**
- Verify: `.gitignore`
- Verify: `.env.example`
- Verify locally: `.env.local`
- Verify: `supabase/config.toml`

**Step 1: Validate the linked project with a read-only command**

Run: `supabase migration list --linked`
Expected: command reaches the linked project without an authentication or password error.

**Step 2: Verify Git safety**

Run: `git check-ignore -v .env.local supabase/.temp/project-ref`
Expected: both local files are ignored.

**Step 3: Verify requested scope**

Run: `find . -type f -name '*.swift' -print`
Expected: no output.

**Step 4: Review repository changes**

Run: `git status --short`
Expected: only safe configuration, example, and plan files appear; `.env.local` and Supabase local state do not appear.
