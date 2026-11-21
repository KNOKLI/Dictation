#ifndef DICT_WHISPER_H
#define DICT_WHISPER_H

/// Загружает модель. Возвращает NULL при ошибке.
void * dw_init(const char * model_path);

/// Распознаёт 16 кГц моно float PCM. Возвращает строку (освободить через dw_free_string) или NULL.
char * dw_transcribe(void * ctx, const float * samples, int n_samples,
                     const char * language, const char * prompt, int n_threads);

void dw_free_string(char * s);
void dw_free(void * ctx);

#endif
