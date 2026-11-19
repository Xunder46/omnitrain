//
//  WatchModalityStart.swift
//  WatchSessionEngine
//
//  The modality grid the watch Start surface wears: four cells, in the phone's
//  home-tile order, with the phone's short labels and the phone's own modality
//  colours.
//
//  Plan: `docs/plans/2026-11-15-176-watch-modality-start-grid-plan/2026-11-15-176-watch-modality-start-grid-plan.md`,
//  D-17602 and D-17605. The rows are the shared contract
//  `watch/contract/watch_modality_start_contract.json`, which the phone's own
//  tokens are held to as well — so neither client can move a colour or a word
//  without the other's suite noticing.
//
//  The watch receives only a theme accent from the phone (`preferences_down`'s
//  `accentColorHex`), so the four colours are constants here rather than synced
//  values. Platform-independent on purpose: the view that draws them is
//  watchOS-only, but the table itself is asserted beside `swift test`.
//

import Foundation

/// The Start surface's modality grid: what it offers, in what order, and what it
/// says about each cell.
public enum WatchModalityStart {
    /// One cell: the modality a tap starts, the word it shows, and its colour.
    public struct Cell: Equatable {
        /// The modality key the started session carries — a `byModality` key, so
        /// the Health type it resolves always has an answer.
        public let key: String

        /// The short label on the cell and in its accessibility sentence.
        public let label: String

        /// The phone's own accent for this modality, as `#RRGGBB`.
        public let hex: String

        public init(key: String, label: String, hex: String) {
            self.key = key
            self.label = label
            self.hex = hex
        }
    }

    /// The four cells, in the phone's home-tile order (D-17602): Cardio,
    /// Resistance, Sports, Isometric.
    public static let cells: [Cell] = [
        Cell(key: "cardio_endurance", label: "Cardio", hex: "#43A047"),
        Cell(key: "resistance_lifting", label: "Resistance", hex: "#5B9BD5"),
        Cell(key: "sports", label: "Sports", hex: "#E63946"),
        Cell(key: "isometric_stretching", label: "Isometric", hex: "#FFA726"),
    ]

    /// What VoiceOver reads for a cell: "Start Cardio workout" and its siblings.
    ///
    /// Built from the contract's single sentence pattern rather than written out
    /// per cell, so a label change moves the spoken words with it.
    public static func startSentence(for label: String) -> String {
        "Start \(label) workout"
    }
}
