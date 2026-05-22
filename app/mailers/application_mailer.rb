class ApplicationMailer < ActionMailer::Base
  default from: -> { AppConfig.get("support_email").presence || "DietVision <noreply@diet-vision.com>" }
  layout "mailer"
end
