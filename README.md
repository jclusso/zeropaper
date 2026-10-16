# ZeroPaper

ZeroPaper is a self-hosted document archive built with Ruby on Rails. It turns scans, PDFs, photos, Word files and spreadsheets into a searchable library.

- **AI providers** through RubyLLM: OpenAI, Anthropic, Google Gemini, Mistral, OpenRouter, DeepSeek, xAI, Ollama or any OpenAI-compatible API. Each task (OCR, document details, Research) can use its own provider and model, and AI can be turned off entirely.
- **OCR** reads scans and photos with a vision model or Mistral Document OCR, with Tesseract or Docling on your machine as the fallback and for private documents. Scans also get a searchable PDF, so text in the viewer can be selected and found.
- **AI metadata** proposes a title, date, correspondent, document type, tags and a summary for each document. You can edit every field, and choose whether AI may create new types and tags or only pick existing ones.
- **Document viewer** shows the PDF, the extracted text, or both side by side, with the text following the page you are on.
- **Hybrid search** combines Postgres full-text search with embeddings computed on your own machine. Dates, correspondents, document types and `#tags` written in a search fill in the filters, all worked out locally. The library filters by several types or tags at once.
- **Research** answers questions across many documents. It shows its progress as it works, cites the documents it used, and saves conversations so you can continue them later.
- **Page cleanup** turns pages that were scanned upside down or sideways upright, and blank page detection finds empty sheets and pages that only show print bleeding through from the other side. It leaves them out of OCR and offers to remove them.
- **Private documents** never leave your machine.
- **Review inbox** collects documents with low-confidence details, possible duplicates, blank pages or processing errors, each with its own fix. Duplicates are found by shared text and can be compared side by side.
- **Rules** file documents automatically: when the text, filename or source matches, set the correspondent and type, add tags, or mark the document private. Correspondents, types and tags can also match by name.
- **Tidy up** correspondents, types and tags: ZeroPaper suggests similar names (plurals, spelling, meaning) and merges them, moving their documents and rules.
- **Import** from uploads (files or whole folders, with progress) and a watched folder.
- **Export and restore** the whole library as one zip file.
- **Sign in** with a password or a passkey. An admin adds other users. Each user picks a light, dark or system theme.

## Private documents

A private document is processed only on your machine:

- Its file, text, filename and details are never sent to a hosted AI provider. Every outbound AI request goes through one check that refuses private documents.
- OCR runs locally with Tesseract or Docling. Details come from Rules and from matching correspondent, type and tag names in the text, and dates are found in the text.
- Its files are stored encrypted on disk with AES-256-GCM, and its text, summary and search passages are encrypted in the database.
- Research searches private documents locally but never sends them to the model. When private documents match a question, the answer lists them as links.

There are four ways to mark a document private:

1. Tick **Private** when uploading.
2. Put the file in the `private/` folder inside the ingest folder.
3. Add a rule with **Mark private** that matches the filename, source or document text. Text conditions are checked against locally read text before anything is sent out.
4. Mark a correspondent as private. Documents that mention it by name are found locally and marked private.

Limits:

- The full-text index (individual words) and the embeddings of private documents are stored unencrypted in Postgres, because search needs them. Someone with access to the database can learn which words a private document contains, but not its full text.
- Marking a document private after it was processed normally deletes what the hosted provider returned and reprocesses it locally. What was already sent to the provider cannot be recalled.
- Encryption keys are derived from `SECRET_KEY_BASE`. Losing it makes private files and encrypted text unreadable.

## Quick start

You need Docker with Compose.

```sh
git clone <this repository> zeropaper
cd zeropaper
cp .env.example .env
# Set SECRET_KEY_BASE (openssl rand -hex 64) and POSTGRES_PASSWORD in .env
mkdir -p ingest/private
docker compose up -d
```

Open http://localhost:3000. The setup wizard creates the admin account, then asks whether to use AI, which provider and models to use, and how to read scans. Everything it asks can be changed later under **Admin**.

The stack has three containers:

| Service | Image | Purpose |
| --- | --- | --- |
| `app` | built from this repository | Web app and background jobs |
| `db` | `pgvector/pgvector:pg18` | Postgres with the pgvector extension |
| `docling` | `quay.io/docling-project/docling-serve-cpu` | Local layout-aware OCR (about 4 GB) |

The first time a document is indexed, the app downloads the embedding model (about 400 MB) into the storage volume. After that, embeddings are computed without any network access.

## Configuration

Settings that take effect at runtime (AI providers and keys, models, OCR, page cleanup, review options, the ingest folder) are under **Admin › Settings**. The environment sets the rest:

| Variable | Purpose |
| --- | --- |
| `SECRET_KEY_BASE` | Required. Signs sessions and derives the encryption keys. |
| `POSTGRES_PASSWORD` | Required. Password for the bundled database. |
| `TZ` | Time zone. Defaults to `UTC`. |
| `DOCLING_URL` | Where Docling runs. Set by Compose; when present, Docling is the default local engine. |
| `PROCESSING_THREADS` | How many documents are processed at once. Defaults to `6`. Each scan uses up to 2 cores for Tesseract, so about half your cores is a good ceiling. |
| `PORT` | Host port for the app. Defaults to `3000`. |
| `APP_HOST` | Host name the app is served under. When set, other hosts are refused. |
| `ASSUME_SSL` | `true` when a reverse proxy terminates TLS. |
| `FORCE_SSL` | `true` to redirect to HTTPS and use secure cookies. |

Passkeys need the app to be reached over HTTPS (or on `localhost`) under a stable host name.

ZeroPaper reads and searches English only for now.

### OCR

When AI is on and an OCR model is chosen, scans are read by that model. The local engine reads private documents, takes over when the AI read fails, and reads everything when AI is off.

| Engine | Runs | Notes |
| --- | --- | --- |
| Vision model | The provider you choose for the OCR task | Good quality on handwriting and photos. |
| Mistral Document OCR | Mistral | Choose `mistral-ocr-latest` as the OCR model. Strong on tables. |
| Tesseract (ocrmypdf) | Locally, in the app container | Always available. Also produces the searchable PDF shown in the viewer. |
| Docling | Locally, in the `docling` container | Better with tables and complex layouts. Slower on CPU. |

Text that is already in the file (PDFs with a text layer, Word, spreadsheets, plain text) is read directly without OCR. Pages turned sideways or upside down are put upright first, and blank pages are skipped; both can be switched off under Page Cleanup.

### Ingest folder

Files placed in `./ingest` are imported within a minute and then removed from the folder. Files in `./ingest/private` are imported as private. Duplicates of documents already in the library are removed without importing. The folder can be switched off or moved under Settings › Ingest Folder; inside Docker a new path must be a mounted volume.

## Backups

Back up three things together:

1. The `.env` file, especially `SECRET_KEY_BASE`.
2. The `storage` volume, which holds the files.
3. The `postgres` volume, or a dump made with `docker compose exec db pg_dump -U zeropaper zeropaper_production`.

**Admin › Export** creates a zip with every document's file, text, details and thumbnail, plus correspondents, types, tags and rules. **Admin › Restore** loads it into this or another ZeroPaper instance, skipping documents that are already there. An export that includes private documents contains them unencrypted, so store it accordingly.

## Development

Requirements:

- [mise](https://mise.jdx.dev) for Ruby (the version is in `.ruby-version`, currently 4.0.7)
- Postgres with the pgvector extension
- The PDF and OCR tools

On macOS:

```sh
brew install postgresql@18 pgvector poppler qpdf tesseract ocrmypdf vips
mise install
bin/setup
bin/dev
```

`bin/dev` runs the web server, the Tailwind watcher and the job workers. Open http://localhost:3000. Restart it after changing `config/queue.yml` or `PROCESSING_THREADS`.

To use Docling during development, run the container and set `DOCLING_URL`:

```sh
docker run -d -p 5001:5001 quay.io/docling-project/docling-serve-cpu:latest
DOCLING_URL=http://localhost:5001 bin/dev
```

Run the tests with:

```sh
bin/rails test
```
