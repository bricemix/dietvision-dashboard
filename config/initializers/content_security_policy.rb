Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    # Scripts : self + nonce (importmap + Stimulus + inline handlers)
    policy.script_src  :self, :unsafe_inline
    # Styles : self + unsafe_inline (Tailwind inline classes)
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
    # Frames : Stripe JS uniquement (pour le Customer Portal iframe)
    policy.frame_src   "https://js.stripe.com", "https://hooks.stripe.com"
    # Frames parents : aucun (protection clickjacking)
    policy.frame_ancestors :none
    # Upgrade HTTP → HTTPS
    policy.upgrade_insecure_requests
  end

  # Nonce préparé — activer après migration de tous les <script> inline vers nonce:
  # config.content_security_policy_nonce_generator = ->(request) { SecureRandom.base64(16) }
  # config.content_security_policy_nonce_directives = %w[script-src]
end
