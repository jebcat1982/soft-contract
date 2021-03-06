(module sat
  (provide
   [sat-solve-7
    ((bool? bool? bool? bool? bool? bool? bool? . -> . bool?) . -> . bool?)])
  
  (define (try f)
    (or (f #t) (f #f)))
  
  (define (sat-solve-7 p)
    (try (λ (n1)
           (try (λ (n2)
                  (try (λ (n3)
                         (try (λ (n4)
                                (try (λ (n5)
                                       (try (λ (n6)
                                              (try (λ (n7)
                                                     (p n1 n2 n3 n4 n5 n6 n7)))))))))))))))))
(module φ
  (provide
   [φ (bool? bool? bool? bool? bool? bool? bool? . -> . bool?)]))

(require sat φ)
(sat-solve-7 φ)