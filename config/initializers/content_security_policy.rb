Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    # Scripts : self + nonce (importmap + Stimulus)
    # unsafe_inline requis pour les handlers onclick inline dans les vues ERB existantes
    policy.script_src  :self, :unsafe_inline
    # Styles : self + unsafe_inline (Tailwind génère des styles inline)
    policy.style_src   :self, :unsafe_inline
    # Images : self, data URIs, HTTPS
    policy.img_src     :self, :data, :https
    # Fonts
    policy.font_src    :self, :data
    # Objets Flash, etc. : aucun
    policy.object_src  :none
    # Connexions XHR/fetch : self + Stripe + OpenRouter
    policy.connect_src :self,
                       "https://api.stripe.com",
                       "https://openrouter.ai",
                       "https://api.resend.com",
                       "https://api.diet-vision.com"
    # Frames : aucune (protection clickjacking)
    policy.frame_ancestors :none
    # Upgrade HTTP → HTTPS
    policy.upgrade_insecure_requests
  end

  # Nonce pour les scripts inline (désactivé pour ne pas casser l'existant rapidement)
  # config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  # config.content_security_policy_nonce_directives = %w[script-src]
end
