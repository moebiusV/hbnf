/* Minimal, self-contained TAILQ macros — a test double for the OpenBSD
 * <sys/queue.h> the generated C includes.  On OpenBSD the real header is used;
 * on other hosts (the Alpine build container) this provides the same TAILQ
 * operations so the emitted tree compiles and runs unchanged. */
#ifndef _SYS_QUEUE_H_
#define _SYS_QUEUE_H_

#define TAILQ_HEAD(name, type) \
    struct name { struct type *tqh_first; struct type **tqh_last; }

#define TAILQ_ENTRY(type) \
    struct { struct type *tqe_next; struct type **tqe_prev; }

#define TAILQ_INIT(head) do { \
    (head)->tqh_first = NULL; \
    (head)->tqh_last = &(head)->tqh_first; \
} while (0)

#define TAILQ_INSERT_HEAD(head, elm, field) do { \
    if (((elm)->field.tqe_next = (head)->tqh_first) != NULL) \
        (head)->tqh_first->field.tqe_prev = &(elm)->field.tqe_next; \
    else \
        (head)->tqh_last = &(elm)->field.tqe_next; \
    (head)->tqh_first = (elm); \
    (elm)->field.tqe_prev = &(head)->tqh_first; \
} while (0)

#define TAILQ_INSERT_TAIL(head, elm, field) do { \
    (elm)->field.tqe_next = NULL; \
    (elm)->field.tqe_prev = (head)->tqh_last; \
    *(head)->tqh_last = (elm); \
    (head)->tqh_last = &(elm)->field.tqe_next; \
} while (0)

#define TAILQ_INSERT_AFTER(head, listelm, elm, field) do { \
    if (((elm)->field.tqe_next = (listelm)->field.tqe_next) != NULL) \
        (elm)->field.tqe_next->field.tqe_prev = &(elm)->field.tqe_next; \
    else \
        (head)->tqh_last = &(elm)->field.tqe_next; \
    (listelm)->field.tqe_next = (elm); \
    (elm)->field.tqe_prev = &(listelm)->field.tqe_next; \
} while (0)

#define TAILQ_INSERT_BEFORE(listelm, elm, field) do { \
    (elm)->field.tqe_prev = (listelm)->field.tqe_prev; \
    (elm)->field.tqe_next = (listelm); \
    *(listelm)->field.tqe_prev = (elm); \
    (listelm)->field.tqe_prev = &(elm)->field.tqe_next; \
} while (0)

#define TAILQ_REMOVE(head, elm, field) do { \
    if (((elm)->field.tqe_next) != NULL) \
        (elm)->field.tqe_next->field.tqe_prev = (elm)->field.tqe_prev; \
    else \
        (head)->tqh_last = (elm)->field.tqe_prev; \
    *(elm)->field.tqe_prev = (elm)->field.tqe_next; \
} while (0)

#define TAILQ_FOREACH(var, head, field) \
    for ((var) = (head)->tqh_first; (var); (var) = (var)->field.tqe_next)

#define TAILQ_FOREACH_REVERSE(var, head, headname, field) \
    for ((var) = (head)->tqh_last->tqe_prev; \
         (var) != &(head)->tqh_first; \
         (var) = (var)->field.tqe_prev)

#define TAILQ_FIRST(head)  ((head)->tqh_first)
#define TAILQ_LAST(head, headname)  (*(((struct headname *)((head)->tqh_last))->tqh_last))
#define TAILQ_NEXT(elm, field)  ((elm)->field.tqe_next)
#define TAILQ_PREV(elm, headname, field)  (*(((struct headname *)((elm)->field.tqe_prev))->tqh_last))
#define TAILQ_EMPTY(head)  ((head)->tqh_first == NULL)

#endif /* _SYS_QUEUE_H_ */
