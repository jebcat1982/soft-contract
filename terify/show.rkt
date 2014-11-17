#lang typed/racket
(require "utils.rkt" "lang.rkt" "closure.rkt")
(require/typed
 redex
 [variables-not-in (Any Any → (Listof Sym))])

(provide (all-defined-out))

(define abstract-V? (make-parameter #t))

(: vars-not-in : Int (Listof Sym) → (Listof Sym))
(define vars-not-in
  (let* ([pool '(x y z u v w a b c)]
         [N (length pool)])
    (λ (n t)
      (reverse ; just for nice order
       (variables-not-in t (if (<= n N) (take pool n) (make-list n 'x1)))))))

(: show-Ans : (case→ [.Ans → (Pairof Any Any)] [.σ .A → (Pairof Any Any)]))
(define show-Ans
  (case-lambda
    [(σ A) (cons (show-E σ A) (show-σ σ))]
    [(Ans) (show-Ans (car Ans) (cdr Ans))]))

(: show-A : .σ .A → Any)
(define (show-A σ A)
  (match A    
    [(.blm l+ lo V C) `(blame ,l+ ,lo ,(show-V σ V) ,(show-V σ C))]
    [(? .V? V) (show-V σ V)]))

(: show-V : (case→ [.σ .V → Any]
                   [.σ (Listof .V) → (Listof Any)]))
(define (show-V σ V)
  (match V
    [(.L i) (if (abstract-V?) (show-V σ (σ@ σ i)) (format "L~a" (n-sub i)))]
    [(.// U C*) (if (.•? U)
                    `(• ,@(for/list : (Listof Any) ([C C*]) (show-V σ C)))
                    (show-U σ U))]
    [(? list? V*) (map (curry show-V σ) V*)]))

(: show-U : .σ .U → Any)
(define (show-U σ U)
  (match U
    [(.b b) (show-b b)]
    [(.•) '•]
    #;[(or (? .Ar?) (.o) (? .λ↓?)) 'function]
    [(? .o? o) (name o)]
    [(.λ↓ f _) (show-e σ f)]
    [(.Ar C V _) `(,(show-V σ C) ◃ ,(show-V σ V))]
    [(.St '¬/c (list (.// (.λ↓ (.λ 1 (.@ (.=) (list (.x 0) e) _) _) _) _))) `(≠/c ,(show-e σ e))]
    [(.St (and n (or 'and/c 'or/c '¬/c)) V*) `(,n ,@(show-V σ V*))]
    [(.St t V*) `(,t ,@(show-V σ V*))]
    [(.Λ/C Cx D v?) `(,@(show-V σ Cx) ,(if v? '↦* '↦) ,(show-E σ D))]
    [(.St/C t V*) `(,(str→sym (str++ (sym→str t) "/c")) ,@(show-V σ V*))]
    [(.μ/C x V) `(μ/C (,x) ,(show-V σ V))]
    [(.X/C x) x]
    [(.Case m) `(case-λ
                 ,@(for/list : (Listof Any) ([(k* v) (in-hash m)])
                     `(,@(for/list : (Listof Any) ([k k*]) (show-V σ k)) ↦ ,(show-V σ v)))
                 [_ ↦ #f])]))

(: show-ρ : .σ .ρ → Any)
(define (show-ρ σ ρ)
  (match-let ([(.ρ m l) ρ])
    (for/list : (Listof Any) ([x (in-hash-keys m)])
      (cond
        [(sym? x) `(,x ↦ ,(show-V σ (hash-ref m x)))]
        [(int? x) `(,(format "sd~a" (n-sub (- l x 1))) ↦ ,(show-V σ (hash-ref m x)))]))))

(: show-E : .σ .E → Any)
(define (show-E σ E)
  (match E
    [(.L i) (str→sym (format "L~a" (n-sub i)))]
    [(? .A? A) (show-A σ A)]
    [(.↓ e ρ) (show-e σ e)]
    [(.FC C V l) `(FC ,l ,(show-E σ C) ,(show-E σ V))]
    [(.Mon C E l³) `(Mon ,l³ ,(show-E σ C) ,(show-E σ E))]
    [(.Assume V C) `(Asm ,(show-E σ V) ,(show-E σ C))]))

(: show-e : .σ .e → Any)
(define (show-e σ e)
  (let go ([ctx : (Listof Sym) '()] [e e])
    (match e
      ; syntactic sugar
      [(.λ 1 (.@ (.=) (list (.x 0) e′) _) _) `(=/c ,(go ctx e′))]
      [(.λ 1 (.@ (.equal?) (list (.x 0) e′) _) _) `(≡/c ,(go ctx e′))]
      [(.λ 1 (.@ (.>) (list (.x 0) e′) _) _) `(>/c ,(go ctx e′))]
      [(.λ 1 (.@ (.<) (list (.x 0) e′) _) _) `(</c ,(go ctx e′))]
      [(.λ 1 (.@ (.≥) (list (.x 0) e′) _) _) `(≥/c ,(go ctx e′))]
      [(.λ 1 (.@ (.≤) (list (.x 0) e′) _) _) `(≤/c ,(go ctx e′))]
      [(.λ 1 (.@ (? closed? f) (list (.x 0)) _) _) (go '() f)]
      [(.λ 1 (.@ (.arity-includes?) (list (.x 0) (.b x)) _) #f) `(arity-includes/c ,x)]
      [(.λ 1 (.@ (.arity=?) (list (.x 0) (.b x)) _) #f) `(arity=/c ,x)]
      [(.λ 1 (.@ (.arity≥?) (list (.x 0) (.b x)) _) #f) `(arity≥/c ,x)]
      [(.@ (.st-mk 'or/c _) (list (.@ (.st-mk '¬/c _) (list c) _) d) _)
       `(⇒/c ,(go ctx c) ,(go ctx d))]
      [(.λ 1 (.b #t) #f) 'any/c]
      [(.λ 1 (.b #f) #f) 'none/c]
      [(.@ (.st-mk (and n 'and/c 'or/c '¬/c) _) c* _) `(,n ,@(map (curry go ctx) c*))]
      [(.@ (.λ n e #f) ex _) (let ([x* (vars-not-in n ctx)])
                               `(let ,(for/list : (Listof Any) ([x (reverse x*)] [ei ex])
                                        `(,x ,(go ctx ei)))
                                  ,(go (append x* ctx) e)))]
      [(.if a b (.b #f)) `(∧ ,(go ctx a) ,(go ctx b))]
      [(.if a b (.b #t)) `(⇒ ,(go ctx a) ,(go ctx b))]
      [(.@ (.λ 1 (.if (.x 0) (.x 0) b) #f) (list a) _)
       `(∨ ,(go ctx a) ,(go (append (vars-not-in 1 ctx) ctx) b))]
      
      [(.λ n e v?)
       (define x* (vars-not-in n ctx))
       `(,(if v? 'λ* 'λ) ,(reverse x*) ,(go (append x* ctx) e))]
      [(.•ₗ α) (syn σ α)]
      [(.b b) (show-b b)]
      [(.st-mk t _) t]
      [(.st-ac 'cons _ 0) 'car]
      [(.st-ac 'cons _ 1) 'cdr]
      [(.st-ac t _ i) (str→sym (str++ (sym→str t) "@" (num→str i)))]
      [(.st-p t _) (str→sym (str++ (sym→str t) "?"))]
      [(.sqrt) '√]
      [(? .o? o) (name o)]
      [(.x i) (ctx-ref ctx i)]
      [(.ref x _ _) x]
      [(.@ f xs _) `(,(go ctx f) ,@(map (curry go ctx) xs))]
      [(.@-havoc x) `(apply ,(go ctx x) •)]
      #;[(.apply f xs _) `(@ ,(go ctx f) ,(go ctx xs))]
      [(.if i t e) `(if ,(go ctx i) ,(go ctx t) ,(go ctx e))]
      [(.amb e*) `(amb ,@(for/list : (Listof Any) ([e e*]) (go ctx e)))]
      [(.μ/c x c) `(μ/c (,x) ,(go ctx c))]
      [(.λ/c c d v?) `(,@(map (curry go ctx) c) ,(if v? '↦* '↦) ,(go ctx d))]
      [(.x/c x) x]
      [(.struct/c t cs) `(,(str→sym (str++ (sym→str t) "/c")) ,@(map (curry go ctx) cs))])))

(: show-b : (U Num Str Bool Sym) → Any)
(define (show-b x)
  (if (str? x) (str++ "\"" x "\"") x))

(: show-σ : .σ → (Listof Any))
(define (show-σ σ)
  (match-define (.σ m _) σ)
  (parameterize ([abstract-V? #f])
    (for/list : (Listof Any) ([(i v) (in-hash m)])
      `(,(str++ "L" (n-sub i)) ↦ ,(show-E σ v)))))

(: ctx-ref : (Listof Sym) Int → Sym)
(define (ctx-ref xs i)
  (let go ([xs xs] [i i])
    (match* (xs i)
      [('() _) (str→sym (str++ (sym→str '⋯) (n-sub i)))]
      [((cons x _) 0) x]
      [((cons _ xr) i) (go xr (- i 1))])))

(: n-sub : Int → String)
(define (n-sub n)
  (cond
   [(< n 0) (format "₋~a" (n-sub (- n)))]
   [(<= 0 n 9) (substring "₀₁₂₃₄₅₆₇₈₉" n (+ n 1))]
   [else (str++ (n-sub (quotient n 10)) (n-sub (remainder n 10)))]))

(: show-ce : .p .σ → (Listof Any))
(define (show-ce p σ)
  (match-define (.p (.m* order ms) _ e†) p)
  #;(printf "σ:~n~ae†:~n~a~n" σ e†)
  (list
   (for*/list : (Listof (Listof Any))
              ([m-name order]
               [m (in-value (hash-ref ms m-name))]
               [m-order (in-value (.m-order m))]
               [defs (in-value (.m-defs m))]
               [res
                (in-value
                 (for*/list : (Listof Any)
                            ([x-name m-order]
                             [v (in-value (car (hash-ref defs x-name)))]
                             #;[_ (in-value (printf "Value is: ~a~n" v))]
                             #:when (.•ₗ? v))
                   `(,x-name : ,(syn σ (.•ₗ-l v)))))]
               #:unless (empty? res))
     `(,m-name : ,@res))
   (show-e σ e†)))

(: syn : .σ Int → Any)
(define (syn σ α)
  (match-define (.σ m _) σ)
  (match (hash-ref m α #f)
    [(? .V? V) (show-V σ (σ@ σ α))]
    [else #f #|ok?|# #;(format "•~a" (n-sub α))]))