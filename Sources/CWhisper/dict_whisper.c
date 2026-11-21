#include "dict_whisper.h"
#include "whisper.h"
#include "ggml-backend.h"
#include <stdlib.h>
#include <string.h>

static void dw_log_noop(enum ggml_log_level level, const char * text, void * user_data) {
    (void)level; (void)text; (void)user_data;
}

void * dw_init(const char * model_path) {
    whisper_log_set(dw_log_noop, NULL);
    ggml_log_set(dw_log_noop, NULL);
    ggml_backend_load_all(); // Metal и CPU грузятся как плагины
    struct whisper_context_params cp = whisper_context_default_params();
    cp.use_gpu = true;
    cp.flash_attn = true;
    return whisper_init_from_file_with_params(model_path, cp);
}

char * dw_transcribe(void * ctx, const float * samples, int n_samples,
                     const char * language, const char * prompt, int n_threads) {
    if (!ctx) return NULL;
    struct whisper_full_params p = whisper_full_default_params(WHISPER_SAMPLING_BEAM_SEARCH);
    p.beam_search.beam_size = 3;
    p.n_threads = n_threads > 0 ? n_threads : 4;
    p.language = (language && language[0]) ? language : "auto";
    p.detect_language = false;
    p.translate = false;
    p.no_timestamps = true;
    p.single_segment = false;
    p.print_progress = false;
    p.print_realtime = false;
    p.print_special = false;
    p.print_timestamps = false;
    p.suppress_blank = true;
    p.suppress_nst = true;
    p.no_context = true;
    p.initial_prompt = (prompt && prompt[0]) ? prompt : NULL;

    struct whisper_context * c = (struct whisper_context *)ctx;
    if (whisper_full(c, p, samples, n_samples) != 0) return NULL;

    int n = whisper_full_n_segments(c);
    size_t cap = 1;
    for (int i = 0; i < n; i++) cap += strlen(whisper_full_get_segment_text(c, i));
    char * out = (char *)malloc(cap);
    if (!out) return NULL;
    out[0] = '\0';
    for (int i = 0; i < n; i++) strcat(out, whisper_full_get_segment_text(c, i));
    return out;
}

void dw_free_string(char * s) { free(s); }

void dw_free(void * ctx) {
    if (ctx) whisper_free((struct whisper_context *)ctx);
}
