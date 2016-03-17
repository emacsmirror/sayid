(ns com.billpiel.sayid.profiling
  (require [com.billpiel.sayid.trace :as tr]
           [com.billpiel.sayid.recording :as rec]
           [com.billpiel.sayid.util.other :as util]))

(defn merge-metric-values
  [a b]
  ((cond (number? a) +
         (set? a) clojure.set/union
         :default (throw (Exception. (format "Cant' merge this: '%s'" a))))
   a b))

(def merge-fn-metrics
  (memoize
   (fn [& rest]
     (apply merge-with
            #(merge-with merge-metric-values % %2)
            rest))))

(defn finalize-metrics
  [fn-ms]
  (util/apply-to-map-vals (fn [metrics]
                            (let [arg-cardinality (-> metrics :arg-set count)
                                  call-count (:count metrics)
                                  gross-time-sum (or (:gross-time-sum metrics) 0)
                                  repeat-arg-pct (- 1 (/ arg-cardinality
                                                         call-count
                                                         1.0))]
                              (-> metrics
                                  (dissoc :arg-set)
                                  (assoc :gross-time-avg (/ gross-time-sum
                                                            call-count
                                                            1.0)
                                         :net-time-avg  (/ (or (:net-time-sum metrics) 0)
                                                           call-count
                                                           1.0)
                                         :arg-cardinality arg-cardinality
                                         :repeat-arg-pct repeat-arg-pct
                                         :gross-of-repeats (* gross-time-sum
                                                              repeat-arg-pct)))))
                          fn-ms))

(defn get-fn-metrics
  [tree]
  (let [{{:keys [gross-time net-time arg-set]} :profiling
         name :name
         children :children} tree
         entry {(keyword name)
                {:count 1
                 :gross-time-sum gross-time
                 :net-time-sum net-time
                 :arg-set arg-set}}]
    (if children
      (apply merge-fn-metrics
             entry
             (map get-fn-metrics
                  children))
      entry)))

(defn add-durations-to-tree
  [tree]
  (let [gross-time (->> tree
                        ((juxt :ended-at :started-at))
                        (apply -))
        children (->> tree
                      :children
                      (mapv add-durations-to-tree))
        kids-time (->> children
                       (map (comp :gross-time :profiling))
                       (apply +))
        net-time (- gross-time kids-time)]
    (assoc tree
           :children children
           :profiling {:gross-time gross-time
                       :net-time net-time
                       :kids-time kids-time
                       :arg-set #{(:args tree)}})))

(defn decorate-tree-with-metrics
  [tree]
  (let [tree' (->> tree
                  :children
                  (mapv add-durations-to-tree)
                  rec/mk-recording)]
    (->> tree'
        :children
        (map get-fn-metrics)
        (apply merge-fn-metrics)
        finalize-metrics
        (assoc tree' :fn-metrics))))

(defn get-report
  [tree])

(defn print-report
  [tree])
