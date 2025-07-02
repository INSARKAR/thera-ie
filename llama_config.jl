# Llama Drug Indication Extractor Configuration

# API Configuration
LLAMA_API_URL = "http://localhost:11434/api/generate"
MODEL_NAME = "llama3.2"

# Directory Paths
DRUG_FILES_DIR = "/users/isarkar/sarkarcode/thera/drug_pubmed_refs"
OUTPUT_DIR = "/users/isarkar/sarkarcode/thera/llama_extracted_indications"

# Processing Settings
MAX_RETRIES = 3
API_DELAY_SECONDS = 1.0
FILE_DELAY_SECONDS = 2.0
CONNECT_TIMEOUT = 30
READ_TIMEOUT = 120

# Model Parameters
TEMPERATURE = 0.1
TOP_P = 0.9
MAX_TOKENS = 1000

# Confidence Threshold (minimum confidence to include in results)
MIN_CONFIDENCE = 0.3

# Batch Processing (if you want to process only a subset)
MAX_FILES_TO_PROCESS = 0  # 0 means process all files
SKIP_EXISTING_OUTPUT = true  # Skip files that already have output

# Logging Level (DEBUG, INFO, WARN, ERROR)
LOG_LEVEL = "INFO"
