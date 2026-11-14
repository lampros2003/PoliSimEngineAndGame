//! What an interface needs to know about a model to build its screens without being
//! written for that model: every named value with its kind, unit, label and help text,
//! and which payments enter and leave each sector.

use crate::model::{DilemmaInfo, Kind, Model};
use crate::program::Ty;
use crate::units::{self, Unit};

#[derive(Clone, Debug, PartialEq)]
pub struct Entry {
    pub name: String,
    pub kind: Kind,
    pub ty: Ty,
    /// Unit of one value, as text: `GBP/household/month`.
    pub unit: String,
    /// Unit of the value shown in results: per-record units multiplied out for totals.
    pub shown_unit: String,
    /// A whole number of minor currency units.
    pub money: bool,
    /// For per-record values, the entity.
    pub entity: Option<String>,
    /// Short name for people: the `label` key, or the name with spaces.
    pub label: String,
    /// The `doc` key, or empty.
    pub doc: String,
    /// Declared limits in stored units (minor units for money).
    pub range: Option<(f64, f64)>,
    pub phase: Option<String>,
    /// Name of this value's column in a result row, if it has one: national values by
    /// name, per-record accounts and flows as `<name>.total`.
    pub row: Option<String>,
    /// For flows: the paying and receiving sectors, and the instrument.
    pub from: Option<String>,
    pub to: Option<String>,
    pub instrument: Option<String>,
    /// A flow marked `financial = true`: a purchase or sale of an asset, such as paying for
    /// gilts, rather than income or spending. Budget screens leave these out.
    pub financial: bool,
    /// A lever the player may set: every lever except those marked `player = false`,
    /// which are inputs that scenarios set (world demand, market rates).
    pub player: bool,
    /// The `group` key: where a policy panel lists it (empty for none).
    pub group: String,
    /// Format 1 (S5.4): "left" or "right" for a lever whose changes are bills, else "".
    pub leaning: String,
    /// Stage S7.3: "good" or "bad" for a situation, else "".
    pub situation: String,
    /// Stage S9.1: for an element a dilemma makes (its lever, its states), the dilemma's
    /// name, else "".
    pub dilemma: String,
    /// Stage S10.5: for an element a lag makes (its var and its chain of states), the
    /// lag's name, else "". Interfaces show the var and may leave the states out.
    pub lag: String,
    /// Format 1: the value's dimensions, by name.
    pub dims: Vec<String>,
    /// Stage S6.1: what this value's formula reads this step, and through `prev()`; for an
    /// account, the flows into and out of it. Filled by [`Catalogue::link`].
    pub inputs: Vec<String>,
    pub lagged_inputs: Vec<String>,
}

/// Format 1: a dimension and its members' labels.
#[derive(Clone, Debug, PartialEq)]
pub struct DimEntry {
    pub name: String,
    pub labels: Vec<String>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct SectorEntry {
    pub name: String,
    pub label: String,
    /// Flows paid to this sector and paid by it, in declaration order.
    pub inflows: Vec<String>,
    pub outflows: Vec<String>,
    /// Accounts held by this sector.
    pub accounts: Vec<String>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Catalogue {
    pub id: String,
    pub currency: String,
    pub minor: i64,
    pub step_unit: String,
    /// Instruments in declaration order; the first is the one payments use by default.
    pub instruments: Vec<String>,
    pub entries: Vec<Entry>,
    pub sectors: Vec<SectorEntry>,
    /// Format 1 (S5.4): the model has a legislature that votes on lever changes.
    pub legislature: bool,
    pub dims: Vec<DimEntry>,
    /// Stage S9.1: the questions put to the player, in order, with their answers. A
    /// dilemma `d` is answered by setting the lever `d` to the answer's position, from 1,
    /// while the state `d_open` is true; `d_choice` is the answer in force.
    pub dilemmas: Vec<DilemmaInfo>,
}

/// `income_tax_total` becomes `Income tax total`.
pub fn humanise(name: &str) -> String {
    let spaced = name.replace('_', " ");
    let mut chars = spaced.chars();
    match chars.next() {
        Some(first) => first.to_uppercase().chain(chars).collect(),
        None => spaced,
    }
}

impl Catalogue {
    /// Stage S6.1: fills each entry's inputs from a simulation of the same model: the
    /// values its formula reads (`deps`, `lagged` by symbol, as the simulation compiled
    /// them) and, for an account, the flows into and out of it. The icon web draws them.
    pub fn link(&mut self, model: &Model, deps: &[Vec<usize>], lagged: &[Vec<usize>]) {
        let names = |ids: &[usize]| ids.iter().map(|i| model.symbols[*i].name.clone()).collect::<Vec<String>>();
        for entry in &mut self.entries {
            let Some(&id) = model.sym_index.get(&entry.name) else { continue };
            entry.inputs = names(deps.get(id).map(Vec::as_slice).unwrap_or_default());
            entry.lagged_inputs = names(lagged.get(id).map(Vec::as_slice).unwrap_or_default());
            // A lag reads what it follows `steps` steps back: one lagged link, not its chain.
            if !entry.lag.is_empty() {
                entry.inputs.clear();
                entry.lagged_inputs.clear();
                if entry.name == entry.lag {
                    let first = model.sym_index.get(&format!("{}__1", entry.lag)).map(|i| &model.symbols[*i]);
                    if let Some(of) = first.and_then(|s| s.spec.get("next")).and_then(|v| v.as_str()) {
                        entry.lagged_inputs.push(of.to_string());
                    }
                }
            }
            if model.symbols[id].kind == Kind::Account {
                let flows: Vec<usize> =
                    model.flows.iter().filter(|f| f.src_account == id || f.dst_account == id).map(|f| f.sym).collect();
                entry.inputs = names(&flows);
            }
        }
    }

    pub fn of(model: &Model) -> Catalogue {
        let sector_name = |account: usize| {
            let account = model.accounts.iter().find(|a| a.sym == account).expect("flows use accounts");
            model.sectors[account.sector].name.clone()
        };
        let mut entries = Vec::with_capacity(model.symbols.len());
        for (id, d) in model.symbols.iter().enumerate() {
            let unit = Some(d.unit.clone());
            let entity = d.entity.map(|e| model.entities[e].name.clone());
            let row = match (d.kind, &entity) {
                (Kind::Param, _) => None,
                // Format 1: dimensioned values are not written cell by cell.
                _ if !d.dims.is_empty() => None,
                (_, None) => Some(d.name.clone()),
                (Kind::Account | Kind::Flow, Some(_)) => Some(format!("{}.total", d.name)),
                _ => None,
            };
            let shown = match &entity {
                Some(e) => units::fmt(&Some(units::mul(&unit, &Some(Unit::base(e))))),
                None => units::fmt(&unit),
            };
            let flow = model.flows.iter().find(|f| f.sym == id);
            let text = |key: &str| d.spec.get(key).and_then(|v| v.as_str()).map(str::to_string);
            entries.push(Entry {
                name: d.name.clone(),
                kind: d.kind,
                ty: d.ty,
                unit: units::fmt(&unit),
                shown_unit: shown,
                money: d.money,
                entity,
                label: text("label").unwrap_or_else(|| humanise(&d.name)),
                doc: text("doc").unwrap_or_default(),
                range: d.range,
                phase: d.phase.map(|p| model.phases[p].clone()),
                row,
                from: flow.map(|f| sector_name(f.src_account)),
                to: flow.map(|f| sector_name(f.dst_account)),
                instrument: flow.map(|f| {
                    let account = model.accounts.iter().find(|a| a.sym == f.src_account).expect("flows use accounts");
                    model.instruments[account.instrument].name.clone()
                }),
                financial: d.spec.get("financial").and_then(|v| v.as_bool()).unwrap_or(false),
                // A dilemma's lever is answered in the dilemma's own dialog, not a policy panel.
                player: d.kind == Kind::Lever
                    && !d.spec.contains_key("dilemma")
                    && d.spec.get("player").and_then(|v| v.as_bool()).unwrap_or(true),
                group: text("group").unwrap_or_default(),
                leaning: text("leaning").unwrap_or_default(),
                situation: if d.kind == Kind::State { text("situation").unwrap_or_default() } else { String::new() },
                dilemma: text("dilemma").unwrap_or_default(),
                lag: text("lag").unwrap_or_default(),
                dims: d.dims.iter().map(|x| model.dims[*x].name.clone()).collect(),
                inputs: Vec::new(),
                lagged_inputs: Vec::new(),
            });
        }
        let sectors = model
            .sectors
            .iter()
            .enumerate()
            .map(|(index, sector)| {
                let in_sector = |account: usize| model.accounts.iter().any(|a| a.sym == account && a.sector == index);
                SectorEntry {
                    name: sector.name.clone(),
                    label: humanise(&sector.name),
                    inflows: model
                        .flows
                        .iter()
                        .filter(|f| in_sector(f.dst_account))
                        .map(|f| model.symbols[f.sym].name.clone())
                        .collect(),
                    outflows: model
                        .flows
                        .iter()
                        .filter(|f| in_sector(f.src_account))
                        .map(|f| model.symbols[f.sym].name.clone())
                        .collect(),
                    accounts: model
                        .accounts
                        .iter()
                        .filter(|a| a.sector == index)
                        .map(|a| model.symbols[a.sym].name.clone())
                        .collect(),
                }
            })
            .collect();
        Catalogue {
            id: model.id.clone(),
            currency: model.currency.clone(),
            minor: model.minor,
            step_unit: units::fmt(&Some(model.step_unit.clone())),
            instruments: model.instruments.iter().map(|i| i.name.clone()).collect(),
            entries,
            sectors,
            legislature: model.legislature.is_some(),
            dims: model.dims.iter().map(|d| DimEntry { name: d.name.clone(), labels: d.labels.clone() }).collect(),
            dilemmas: model.dilemmas.clone(),
        }
    }

    pub fn entry(&self, name: &str) -> Option<&Entry> {
        self.entries.iter().find(|e| e.name == name)
    }

    /// The entry whose result-row column is `row` (`hh_money.total` gives `hh_money`).
    pub fn by_row(&self, row: &str) -> Option<&Entry> {
        self.entries.iter().find(|e| e.row.as_deref() == Some(row))
    }
}
