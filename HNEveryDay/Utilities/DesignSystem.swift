//
//  DesignSystem.swift
//  HNEveryDay
//
//  Design System & Tokens based on Apple Design Guidelines & Emil Kowalski Design Engineering.
//

import SwiftUI
import UIKit

public enum AppTheme {
  
  // MARK: - Touch & Gesture Feedback Tokens
  public enum Touch {
    public static let pressScale: CGFloat = 0.978
    public static let pressAnimationDuration: Double = 0.12
  }
  
  // MARK: - Spring Physics Tokens (Apple Damped Physics)
  public enum Spring {
    /// Fluid spring for gesture handoffs, drawers, and folding nodes (stiffness: 300, damping: 28)
    public static var fluid: Animation {
      .interpolatingSpring(stiffness: 300, damping: 28)
    }
    
    /// Bouncy spring for flick/momentum interactions (bounce: 0.15, duration: 0.35)
    public static var momentum: Animation {
      .spring(duration: 0.35, bounce: 0.15)
    }
    
    /// Quick snappy spring for tooltips / small chips (duration: 0.2, bounce: 0.0)
    public static var snappy: Animation {
      .spring(duration: 0.2, bounce: 0.0)
    }
  }
  
  // MARK: - Typography & Optical Sizing Tokens
  public enum Typography {
    /// Negative tracking for large display headers (>= 15pt) to tighten spacing
    public static let titleTracking: CGFloat = -0.2
    /// Positive tracking for small monospaced metadata (<= 11pt) to increase legibility
    public static let metadataTracking: CGFloat = 0.1
  }
  
  // MARK: - Haptic Feedback Helpers
  public enum Haptics {
    public static func playSoftImpact() {
      let generator = UIImpactFeedbackGenerator(style: .soft)
      generator.prepare()
      generator.impactOccurred()
    }
    
    public static func playLightImpact() {
      let generator = UIImpactFeedbackGenerator(style: .light)
      generator.prepare()
      generator.impactOccurred()
    }
    
    public static func playSuccessNotification() {
      let generator = UINotificationFeedbackGenerator()
      generator.prepare()
      generator.notificationOccurred(.success)
    }
  }
}

// MARK: - Instant Touch Down Feedback Button Style
public struct TactileButtonStyle: ButtonStyle {
  public init() {}
  
  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? AppTheme.Touch.pressScale : 1.0)
      .animation(.easeOut(duration: AppTheme.Touch.pressAnimationDuration), value: configuration.isPressed)
      .onChange(of: configuration.isPressed) { _, isPressed in
        if isPressed {
          AppTheme.Haptics.playSoftImpact()
        }
      }
  }
}

extension ButtonStyle where Self == TactileButtonStyle {
  public static var tactile: TactileButtonStyle { TactileButtonStyle() }
}
