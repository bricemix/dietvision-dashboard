# encoding: UTF-8
# Templates de notifications push localisés, par déclencheur automatique.
module PushTemplates
  T = {
    inactive_3d: {
      "fr" => { title: "On t'a manqué ! 👋", body: "Scanne ton repas du jour pour rester dans tes objectifs." },
      "en" => { title: "We missed you! 👋", body: "Scan today's meal to stay on track with your goals." },
      "de" => { title: "Wir haben dich vermisst! 👋", body: "Scanne deine heutige Mahlzeit und bleib auf Kurs." },
      "es" => { title: "¡Te echamos de menos! 👋", body: "Escanea tu comida de hoy para seguir con tus objetivos." },
      "pt" => { title: "Sentimos sua falta! 👋", body: "Escaneie sua refeição de hoje para manter seus objetivos." }
    },
    inactive_7d: {
      "fr" => { title: "Reprends ta progression 💪", body: "Une semaine sans suivi ? Ton coach IA t'attend dans l'app." },
      "en" => { title: "Get back on track 💪", body: "A week without tracking? Your AI coach is waiting in the app." },
      "de" => { title: "Mach weiter 💪", body: "Eine Woche ohne Tracking? Dein KI-Coach wartet in der App." },
      "es" => { title: "Retoma tu progreso 💪", body: "¿Una semana sin seguimiento? Tu coach IA te espera en la app." },
      "pt" => { title: "Retome seu progresso 💪", body: "Uma semana sem registrar? Seu coach IA espera você no app." }
    },
    trial_ending: {
      "fr" => { title: "Ton essai se termine bientôt ⏳", body: "-40% sur l'abonnement annuel. Ne perds pas ta progression !" },
      "en" => { title: "Your trial is ending soon ⏳", body: "-40% on the annual plan. Don't lose your progress!" },
      "de" => { title: "Dein Test endet bald ⏳", body: "-40% auf das Jahresabo. Verliere deinen Fortschritt nicht!" },
      "es" => { title: "Tu prueba termina pronto ⏳", body: "-40% en el plan anual. ¡No pierdas tu progreso!" },
      "pt" => { title: "Seu teste termina em breve ⏳", body: "-40% no plano anual. Não perca seu progresso!" }
    },
    winback: {
      "fr" => { title: "Reviens quand tu veux 💚", body: "Ton accès Premium et ta progression t'attendent. Réactive en 1 clic." },
      "en" => { title: "Come back anytime 💚", body: "Your Premium access and progress are waiting. Reactivate in 1 tap." },
      "de" => { title: "Komm jederzeit zurück 💚", body: "Dein Premium-Zugang und Fortschritt warten. Reaktiviere in 1 Tipp." },
      "es" => { title: "Vuelve cuando quieras 💚", body: "Tu acceso Premium y tu progreso te esperan. Reactiva en 1 toque." },
      "pt" => { title: "Volte quando quiser 💚", body: "Seu acesso Premium e progresso esperam você. Reative com 1 toque." }
    }
  }.freeze

  # Retourne {title:, body:} pour un déclencheur + locale (fallback fr).
  def self.for(key, locale)
    loc = locale.to_s
    loc = "en" if loc == "us"
    set = T[key.to_sym] || {}
    set[loc] || set["fr"]
  end
end
