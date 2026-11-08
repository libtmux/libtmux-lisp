(in-package #:libtmux.internal)

(defun text-argument (value &optional (name "Text") (empty-p t))
  (unless (and (stringp value) (not (find #\Null value))
               (or empty-p (plusp (length value))))
    (invalid-argument "~A must be a ~Astring without NUL" name (if empty-p "" "nonempty ")))
  (copy-seq value))

(defun integer-argument (value minimum maximum name)
  (unless (and (integerp value) (<= minimum value maximum))
    (invalid-argument "~A must be an integer from ~D through ~D" name minimum maximum))
  (write-to-string value :base 10 :radix nil))

(defun literal-format (text)
  (let* ((text (text-argument text)) (length (length text)) (index 0))
    (with-output-to-string (stream)
      (loop while (< index length)
            do (if (char= (char text index) #\#)
                   (let ((end (or (position-if-not (lambda (character) (char= character #\#))
                                                   text :start index)
                                  length)))
                     ;; Tmux preserves hash runs before [ for its later style renderer.
                     (write-string text stream :start index :end end)
                     (unless (and (< end length) (char= (char text end) #\[))
                       (write-string text stream :start index :end end))
                     (setf index end))
                   (progn (write-char (char text index) stream) (incf index)))))))

(defun quote-tmux-token (text)
  ;; Literal newlines in tmux quotes strip following whitespace/comments.
  (with-output-to-string (stream)
    (write-char #\" stream)
    (loop for character across (text-argument text)
          for code = (char-code character)
          do (if (or (< code 32) (= code 127) (find character '(#\$ #\~ #\\ #\")))
                 (format stream "\\~3,'0O" code)
                 (write-char character stream)))
    (write-char #\" stream)))

(defun tmux-command-text (arguments)
  (format nil "~{~A~^ ~}" (map 'list #'quote-tmux-token (argument-vector arguments))))

(defun tmux-command-list (commands)
  (format nil "~{~A~^ ; ~}" (mapcar #'tmux-command-text commands)))

(defun pane-command-arguments (command shell-command &key (command-p (not (null command)))
                                                         (shell-command-p (not (null shell-command))))
  (when (and command-p shell-command-p)
    (invalid-argument "Specify command argv or shell-command, not both"))
  (cond
    (shell-command-p (list (text-argument shell-command "Shell command")))
    (command-p
     (let ((arguments (coerce (argument-vector command) 'list)))
       (unless (and arguments (plusp (length (first arguments)))
                    (not (char= #\- (char (first arguments) 0))))
         (invalid-argument "Command argv needs a nonempty, path-qualified leading-dash executable"))
       (if (= 1 (length arguments))
           (append '("/bin/sh" "-c" "exec \"$@\"" "libtmux-exec") arguments)
           arguments)))
    (t nil)))

(defun check-command-envelope (arguments)
  ;; Linux tmux's 16,384-byte imsg also carries a 16-byte header and 4-byte argc.
  (when (> (loop for argument in arguments sum (1+ (length (encode-utf8 argument)))) 16000)
    (invalid-argument "Encoded tmux command exceeds 16,000 bytes; use an explicit byte-input operation"))
  arguments)

(defun environment-arguments (environment)
  (loop for entry across (finite-vector environment "Environment")
        append (progn
                 (unless (and (consp entry) (stringp (car entry)) (stringp (cdr entry)))
                   (invalid-argument "Environment must contain (name . value) string pairs"))
                 (let ((name (text-argument (car entry) "Environment name" nil))
                       (value (text-argument (cdr entry) "Environment value")))
                   (when (find #\= name) (invalid-argument "Environment names cannot contain ="))
                   (list "-e" (concatenate 'string name "=" value))))))

(defun physical-target (entity model)
  (unless (and (typep entity 'libtmux:entity) (eq model (libtmux:entity-model entity)))
    (invalid-argument "Expected a captured ~A target" model))
  (libtmux:id entity))

(defun link-target (link)
  (destructuring-bind (session index window) (physical-target link :window-link)
    (declare (ignore window))
    (format nil "~A:~D" session index)))

(defun session-index-target (session index)
  (concatenate 'string (physical-target session :session) ":"
               (integer-argument index 0 2147483647 "Window index")))

(defun split-flags (direction size percent before full-size detached)
  (unless (member direction '(:horizontal :vertical))
    (invalid-argument "Split direction must be :horizontal or :vertical"))
  (when (and size percent) (invalid-argument "Specify split size or percent, not both"))
  (append (list (if (eq direction :horizontal) "-h" "-v"))
          (when detached '("-d")) (when before '("-b")) (when full-size '("-f"))
          (when size (list "-l" (integer-argument size 1 2147483647 "Split size")))
          (when percent (list "-l" (concatenate 'string (integer-argument percent 1 100 "Split percent") "%")))))
