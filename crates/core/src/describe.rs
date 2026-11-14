//! What an interface needs to know about a model to build its screens without being
//! written for that model: every named value with its kind, unit, label and help text,
//! and which payments enter and leave each sector.

use crate::model::{Kind, Model};
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
    /// Format 1: the value's dimensions, by name.
    pub dims: Vec<String>,
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
    pub dims: Vec<DimEntry>,
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
                player: d.kind == Kind::Lever && d.spec.get("player").and_then(|v| v.as_bool()).unwrap_or(true),
                group: text("group").unwrap_or_default(),
                dims: d.dims.iter().map(|x| model.dims[*x].name.clone()).collect(),
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
            dims: model.dims.iter().map(|d| DimEntry { name: d.name.clone(), labels: d.labels.clone() }).collect(),
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
