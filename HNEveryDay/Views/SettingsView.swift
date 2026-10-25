//
//  SettingsView.swift
//  HNEveryDay
//
//  Created by AI on 01/01/2026.
//

import SwiftUI

struct SettingsView: View {
  // AI Configuration - hosted by default; BYOK keys are stored in Keychain
  @State private var aiMode: AIMode = AIMode.current
  @State private var modelDisclosure: String?
  @State private var apiKey: String = ""
  @AppStorage("ai_base_url") private var baseURL: String = AIDefaults.baseURL
  @AppStorage("ai_model") private var model: String = AIDefaults.model

  // General Settings
  @AppStorage("preferred_language") private var preferredLanguage: String = "system"
  @AppStorage("translation_mode") private var translationMode: String = TranslationMode.off.rawValue
  @AppStorage("cache_retention_days") private var cacheRetentionDays: Int = 30

  @Environment(\.dismiss) private var dismiss

  private var appVersion: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1"
  }

  // Provider Preset Logic
  enum ProviderPreset: String, CaseIterable, Identifiable {
    case openai = "OpenAI"
    case deepseek = "DeepSeek"
    case qwen = "Qwen (Aliyun)"
    case glm = "ChatGLM (Zhipu)"
    case doubao = "Doubao (ByteDance)"
    case gemini = "Gemini (OpenAI Compatibility)"
    case custom = "Custom / Local"

    var id: String { rawValue }

    var defaultBaseURL: String {
      switch self {
      case .openai: return "https://api.openai.com/v1"
      case .deepseek: return AIDefaults.baseURL
      case .qwen: return "https://dashscope.aliyuncs.com/compatible-mode/v1"
      case .glm: return "https://open.bigmodel.cn/api/paas/v4"
      case .doubao: return "https://ark.cn-beijing.volces.com/api/v3"
      case .gemini: return "https://generativelanguage.googleapis.com/v1beta/openai"
      case .custom: return ""
      }
    }

    var defaultModel: String {
      return suggestedModels.first ?? ""
    }

    var suggestedModels: [String] {
      switch self {
      case .openai: return ["gpt-4o-mini", "gpt-4o", "gpt-3.5-turbo"]
      case .deepseek: return [AIDefaults.model, "deepseek-chat", "deepseek-coder"]
      case .qwen: return ["qwen-turbo", "qwen-plus", "qwen-max"]
      case .glm: return ["glm-4", "glm-4-air", "glm-3-turbo"]
      case .doubao: return []  // Requires ID, no generic name
      case .gemini: return ["gemini-1.5-flash", "gemini-1.5-pro", "gemini-pro"]
      case .custom: return ["llama3", "mistral", "gemma"]
      }
    }
  }

  @State private var selectedProvider: ProviderPreset = .deepseek

  var body: some View {
    NavigationStack {
      Form {
        // MARK: - Membership
        if aiMode == .hosted {
          ProStatusSection()
        }

        // MARK: - AI Service
        Section {
          Picker("AI Service", selection: $aiMode) {
            Text("Hosted", comment: "Hosted AI mode").tag(AIMode.hosted)
            Text("Own API Key", comment: "Bring your own key mode").tag(AIMode.byok)
          }
          .pickerStyle(.segmented)
          .onChange(of: aiMode) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: AIMode.defaultsKey)
          }
        } header: {
          Text("AI Service", comment: "Section header")
        } footer: {
          if aiMode == .hosted {
            VStack(alignment: .leading, spacing: 6) {
              Text(
                "Works out of the box. Shared translations and summaries are served from the HNEveryDay cache; new summaries and article translations count toward a daily allowance.",
                comment: "Hosted mode explanation")
              if let modelDisclosure {
                Text(modelDisclosure)
              }
            }
          } else {
            Text(
              "Advanced: your questions and articles go directly to your own provider with your key, with no daily limits. Only suggested questions for a story are fetched from HNEveryDay.",
              comment: "BYOK mode explanation")
          }
        }

        if aiMode == .byok {
          // MARK: - Provider Picker
          Section {
            Picker("Provider Preset", selection: $selectedProvider) {
              ForEach(ProviderPreset.allCases) { provider in
                Text(provider.rawValue).tag(provider)
              }
            }
            .onChange(of: selectedProvider) { _, newValue in
              if newValue != .custom {
                baseURL = newValue.defaultBaseURL
                model = newValue.defaultModel
              }
            }
          } header: {
            Text("Quick Setup", comment: "Section header")
          }

          // MARK: - Credentials
          Section {
            SecureField("sk-...", text: $apiKey)
              .onChange(of: apiKey) { _, newValue in
                _ = KeychainHelper.save(key: "ai_api_key", value: newValue)
              }
          } header: {
            Text("API Key", comment: "Section header")
          } footer: {
            Text("Your key is stored securely in Keychain.", comment: "Security note")
          }

          // MARK: - Advanced Config
          Section("Configuration") {
            TextField("Base URL", text: $baseURL)
              .keyboardType(.URL)
              .autocorrectionDisabled()
              .textInputAutocapitalization(.never)

            VStack(alignment: .leading, spacing: 4) {
              HStack {
                TextField("Model Name", text: $model)
                  .autocorrectionDisabled()
                  .textInputAutocapitalization(.never)

                // Suggestions Menu
                if !selectedProvider.suggestedModels.isEmpty {
                  Menu {
                    ForEach(selectedProvider.suggestedModels, id: \.self) { suggestion in
                      Button(suggestion) {
                        model = suggestion
                      }
                    }
                  } label: {
                    Image(systemName: "chevron.up.chevron.down")
                      .foregroundStyle(.secondary)
                      .padding(.horizontal, 4)
                      .background(Color.secondary.opacity(0.1))
                      .clipShape(RoundedRectangle(cornerRadius: 6))
                  }
                }
              }

              if selectedProvider == .doubao {
                Text("Note: For Doubao, enter your Endpoint ID (e.g., ep-2024...) here.")
                  .font(.caption2)
                  .foregroundStyle(.orange)
              }
            }
          }

          if selectedProvider == .custom {
            Section {
              Text(
                "Supports any OpenAI-compatible server (e.g. Ollama, LM Studio). Set Base URL to 'http://localhost:11434/v1' for Ollama."
              )
              .font(.caption)
              .foregroundStyle(.secondary)
            }
          }
        }

        // MARK: - General Settings
        Section {
          Picker("AI Response Language", selection: $preferredLanguage) {
            Text("System Default", comment: "Follow device language").tag("system")
            ForEach(ReadingLanguage.supportedOptions) { language in
              Text(language.label).tag(language.code)
            }
          }

          Picker("Article Translation", selection: $translationMode) {
            Text("Off", comment: "Disable article translation").tag(TranslationMode.off.rawValue)
            Text("On Demand", comment: "Translate when requested").tag(TranslationMode.onDemand.rawValue)
            Text("Auto When Needed", comment: "Translate when article language differs").tag(
              TranslationMode.auto.rawValue)
          }

          Stepper(
            "Keep History: \(cacheRetentionDays) Days", value: $cacheRetentionDays, in: 7...90,
            step: 7)
        } header: {
          Text("General", comment: "Section header")
        } footer: {
          Text(
            "Translations are cached locally with read articles.",
            comment: "Translation explanation")
        }

        // MARK: - About
        Section("About") {
          LabeledContent("Version", value: appVersion)
          NavigationLink {
            LegalLinks.privacyPolicyView
          } label: {
            Text("Privacy Policy")
          }
          Link(destination: LegalLinks.termsOfUse) {
            HStack {
              Text("Terms of Use")
              Spacer()
              Image(systemName: "arrow.up.right.square")
                .foregroundStyle(.secondary)
            }
          }
          Link(destination: URL(string: "https://github.com/corlin/HNEveryDay")!) {
            HStack {
              Text("GitHub")
              Spacer()
              Image(systemName: "arrow.up.right.square")
                .foregroundStyle(.secondary)
            }
          }
        }
      }
      .navigationTitle(Text("Settings", comment: "Page title"))
      .task {
        modelDisclosure = await RemoteConfigStore.shared.current().model_disclosure
      }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") {
            dismiss()
          }
        }
      }
    }
    .onAppear {
      // Load API key from Keychain
      apiKey = KeychainHelper.read(key: "ai_api_key") ?? ""

      // Detect provider from URL
      if let match = ProviderPreset.allCases.first(where: {
        baseURL.contains($0.defaultBaseURL) && $0 != .custom
      }) {
        selectedProvider = match
      } else {
        selectedProvider = .custom
      }
    }
  }
}

#Preview {
  SettingsView()
}
