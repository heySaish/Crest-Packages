# Crest Debian APT Repository (Crest-Packages)

Official Debian APT repository foundation for Crest Debian with GPG signature support and GitHub Actions automation.

## Architecture & Directory Layout

The repository follows standard Debian APT archive specifications:

```
Crest-Packages/
├── .github/
│   └── workflows/
│       └── publish-apt-repo.yml   # GitHub Actions workflow (GPG signing & Pages deployment)
├── dists/
│   └── stable/
│       ├── main/
│       │   └── binary-arm64/      # Generated index metadata (Packages, Packages.gz)
│       ├── Release                # Repository Release file (MD5/SHA256 checksums)
│       ├── Release.gpg            # Detached GPG signature of Release
│       └── InRelease              # Clearsigned GPG signature of Release
├── pool/
│   └── main/                      # Binary package pool organized by initial letter
│       └── c/
│           └── crest-dummy/
│               ├── crest-dummy_1.0.0_arm64.deb
│               └── crest-dummy_1.0.1_arm64.deb
├── scripts/
│   └── generate-apt-repo.sh       # Metadata generation & GPG signing script
├── crest-archive-keyring.gpg      # Public GPG key for client trust verification
├── LICENSE
└── README.md
```

---

## Production GitHub Actions Workflow Setup

The production pipeline automatically imports the repository signing key, generates indices, signs `Release` files, verifies signatures, and publishes the static APT repository to GitHub Pages.

```
                  [Git Push to main]
                          │
                          ▼
            [GitHub Actions CI Job Starts]
                          │
                          ▼
    [Check Secrets: GPG_PRIVATE_KEY & GPG_PASSPHRASE]
    ├── If missing: Fails safely (exit 1) — prevents unsigned deployment
    └── If present: Imports private key into isolated temporary GNUPGHOME
                          │
                          ▼
         [generate-apt-repo.sh (REQUIRE_GPG_SIGNING=1)]
         ├── Generates Packages, Packages.gz & Release
         └── Signs Release -> Release.gpg & InRelease
                          │
                          ▼
        [Verification: gpg --verify Release.gpg & InRelease]
                          │
                          ▼
     [Export Public Key: crest-archive-keyring.gpg]
                          │
                          ▼
         [Deploy Output to GitHub Pages]
```

---

## Required GitHub Repository Secrets

To enable production GPG signing on GitHub Actions:

Navigate to **Repository Settings -> Secrets and variables -> Actions** and add:

| Secret Name | Required? | Description & Format |
|---|---|---|
| `GPG_PRIVATE_KEY` | **Required** | ASCII-armored OpenPGP private key block. Export via `gpg --armor --export-secret-keys <KEY-ID>`. |
| `GPG_PASSPHRASE` | *Optional* | Passphrase protecting the GPG private key (if configured during key generation). |

> [!CAUTION]
> **SECURITY WARNING**:
> - NEVER commit private keys into Git or track key files in the repository.
> - NEVER hardcode secrets in scripts or GitHub Actions workflow YAML.
> - The CI workflow imports private keys into an isolated `mktemp -d` workspace that is automatically wiped on job completion (`trap 'rm -rf "$GNUPGHOME"' EXIT`).

---

## Client Configuration (`signed-by=`)

To configure Crest Debian clients to trust and consume packages:

1. Download the public signing keyring:
   ```bash
   sudo mkdir -p /usr/share/keyrings
   curl -fsSL https://<username>.github.io/Crest-Packages/crest-archive-keyring.gpg | sudo tee /usr/share/keyrings/crest-archive-keyring.gpg > /dev/null
   ```

2. Add repository source to `/etc/apt/sources.list.d/crest.list`:
   ```bash
   echo "deb [signed-by=/usr/share/keyrings/crest-archive-keyring.gpg] https://<username>.github.io/Crest-Packages stable main" | sudo tee /etc/apt/sources.list.d/crest.list
   ```

3. Update APT indices and install packages:
   ```bash
   sudo apt update
   sudo apt install crest-dummy
   ```

---

## Local Development (Unsigned Mode)

For local development where no GPG key is imported:
```bash
# Generate unsigned local repository metadata
bash scripts/generate-apt-repo.sh

# Configure local Debian test source
echo "deb [trusted=yes] file:///path/to/Crest-Packages stable main" | sudo tee /etc/apt/sources.list.d/crest.list
```
