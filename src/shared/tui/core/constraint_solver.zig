//! Constraint-based layout solver for TUI applications
//!
//! This module implements a linear constraint solver using the simplex algorithm,
//! designed for efficient UI layout calculations. It supports:
//! - Equality and inequality constraints
//! - Priority levels (required, strong, medium, weak)
//! - Efficient solving for typical UI layout scenarios
//! - Integration hooks for existing layout systems
//!
//! Example usage:
//! ```zig
//! var solver = ConstraintSolver.init(allocator);
//! defer solver.deinit();
//!
//! const width = try solver.createVariable("width");
//! const height = try solver.createVariable("height");
//!
//! // Add constraint: width = 2 * height
//! var expr = Expression.init(allocator);
//! try expr.addTerm(width.id, 1.0);
//! try expr.addTerm(height.id, -2.0);
//! try solver.addConstraint(expr, .equal, .required);
//!
//! // Suggest preferred values
//! try solver.suggestValue(width, 100.0);
//!
//! try solver.solve();
//! ```

const std = @import("std");
const math = std.math;
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;

/// Priority levels for constraints
pub const Priority = enum(u32) {
    required = 1000,
    strong = 750,
    medium = 500,
    weak = 250,

    pub fn value(self: Priority) f64 {
        return @floatFromInt(@intFromEnum(self));
    }
};

/// Relation types for constraints
pub const Relation = enum {
    equal,
    less_than_or_equal,
    greater_than_or_equal,
};

/// Variable in the constraint system
pub const Variable = struct {
    id: u32,
    name: []const u8,
    value: f64,
    is_external: bool,
    is_basic: bool,
    row_index: ?usize,

    pub fn init(id: u32, name: []const u8) Variable {
        return .{
            .id = id,
            .name = name,
            .value = 0.0,
            .is_external = true,
            .is_basic = false,
            .row_index = null,
        };
    }
};

/// Linear expression: a*x + b*y + c*z + constant
pub const Expression = struct {
    terms: ArrayList(Term),
    constant: f64,
    allocator: Allocator,

    pub const Term = struct {
        variable_id: u32,
        coefficient: f64,
    };

    pub fn init(allocator: Allocator) Expression {
        return .{
            .terms = ArrayList(Term).init(allocator),
            .constant = 0.0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Expression) void {
        self.terms.deinit();
    }

    pub fn clone(self: *const Expression) !Expression {
        var new_expr = Expression.init(self.allocator);
        try new_expr.terms.appendSlice(self.terms.items);
        new_expr.constant = self.constant;
        return new_expr;
    }

    pub fn addTerm(self: *Expression, variable_id: u32, coefficient: f64) !void {
        // Check if variable already exists in expression
        for (self.terms.items) |*term| {
            if (term.variable_id == variable_id) {
                term.coefficient += coefficient;
                if (@abs(term.coefficient) < 1e-10) {
                    // Remove near-zero terms
                    const index = (@intFromPtr(term) - @intFromPtr(self.terms.items.ptr)) / @sizeOf(Term);
                    _ = self.terms.orderedRemove(index);
                }
                return;
            }
        }

        if (@abs(coefficient) >= 1e-10) {
            try self.terms.append(.{
                .variable_id = variable_id,
                .coefficient = coefficient,
            });
        }
    }

    pub fn addConstant(self: *Expression, value: f64) void {
        self.constant += value;
    }

    pub fn multiply(self: *Expression, factor: f64) void {
        for (self.terms.items) |*term| {
            term.coefficient *= factor;
        }
        self.constant *= factor;
    }

    pub fn evaluate(self: *const Expression, variables: *const AutoHashMap(u32, *Variable)) f64 {
        var result = self.constant;
        for (self.terms.items) |term| {
            if (variables.get(term.variable_id)) |var_ptr| {
                result += term.coefficient * var_ptr.value;
            }
        }
        return result;
    }
};

/// Constraint in the system
pub const Constraint = struct {
    id: u32,
    expression: Expression,
    relation: Relation,
    priority: Priority,
    slack_variable_id: ?u32,
    error_variable_ids: struct {
        plus: ?u32,
        minus: ?u32,
    },

    pub fn init(id: u32, expression: Expression, relation: Relation, priority: Priority) Constraint {
        return .{
            .id = id,
            .expression = expression,
            .relation = relation,
            .priority = priority,
            .slack_variable_id = null,
            .error_variable_ids = .{ .plus = null, .minus = null },
        };
    }

    pub fn deinit(self: *Constraint) void {
        self.expression.deinit();
    }
};

/// Tableau row for simplex algorithm
const TableauRow = struct {
    basic_variable_id: u32,
    expression: Expression,

    pub fn init(basic_variable_id: u32, expression: Expression) TableauRow {
        return .{
            .basic_variable_id = basic_variable_id,
            .expression = expression,
        };
    }

    pub fn deinit(self: *TableauRow) void {
        self.expression.deinit();
    }
};

/// Main constraint solver using simplex algorithm
pub const ConstraintSolver = struct {
    allocator: Allocator,
    variables: AutoHashMap(u32, *Variable),
    constraints: ArrayList(*Constraint),
    tableau: ArrayList(TableauRow),
    objective_row: Expression,
    next_variable_id: u32,
    next_constraint_id: u32,
    epsilon: f64,

    pub fn init(allocator: Allocator) ConstraintSolver {
        return .{
            .allocator = allocator,
            .variables = AutoHashMap(u32, *Variable).init(allocator),
            .constraints = ArrayList(*Constraint).init(allocator),
            .tableau = ArrayList(TableauRow).init(allocator),
            .objective_row = Expression.init(allocator),
            .next_variable_id = 0,
            .next_constraint_id = 0,
            .epsilon = 1e-8,
        };
    }

    pub fn deinit(self: *ConstraintSolver) void {
        // Clean up variables
        var var_iter = self.variables.iterator();
        while (var_iter.next()) |entry| {
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.variables.deinit();

        // Clean up constraints
        for (self.constraints.items) |constraint| {
            constraint.deinit();
            self.allocator.destroy(constraint);
        }
        self.constraints.deinit();

        // Clean up tableau
        for (self.tableau.items) |*row| {
            row.deinit();
        }
        self.tableau.deinit();

        self.objective_row.deinit();
    }

    pub fn createVariable(self: *ConstraintSolver, name: []const u8) !*Variable {
        const variable = try self.allocator.create(Variable);
        variable.* = Variable.init(self.next_variable_id, name);
        self.next_variable_id += 1;

        try self.variables.put(variable.id, variable);
        return variable;
    }

    pub fn addConstraint(self: *ConstraintSolver, expression: Expression, relation: Relation, priority: Priority) !void {
        const constraint = try self.allocator.create(Constraint);
        constraint.* = Constraint.init(self.next_constraint_id, expression, relation, priority);
        self.next_constraint_id += 1;

        // Add slack and error variables based on constraint type and priority
        if (priority != .required) {
            // Add error variables for non-required constraints
            const error_plus = try self.createVariable("error+");
            const error_minus = try self.createVariable("error-");
            error_plus.is_external = false;
            error_minus.is_external = false;

            constraint.error_variable_ids.plus = error_plus.id;
            constraint.error_variable_ids.minus = error_minus.id;

            // Add error terms to objective function with weighted priority
            const weight = priority.value();
            try self.objective_row.addTerm(error_plus.id, weight);
            try self.objective_row.addTerm(error_minus.id, weight);
        }

        // Add slack variable for inequality constraints
        switch (relation) {
            .less_than_or_equal, .greater_than_or_equal => {
                const slack = try self.createVariable("slack");
                slack.is_external = false;
                constraint.slack_variable_id = slack.id;
            },
            .equal => {},
        }

        try self.constraints.append(constraint);
        try self.addToTableau(constraint);
    }

    fn addToTableau(self: *ConstraintSolver, constraint: *Constraint) !void {
        var expr = try constraint.expression.clone();
        defer expr.deinit();

        // Handle different constraint types
        switch (constraint.relation) {
            .equal => {
                if (constraint.priority == .required) {
                    // For required equality, add directly to tableau
                    const basic_var = try self.findOrCreateBasicVariable(&expr);
                    try self.tableau.append(TableauRow.init(basic_var.id, try expr.clone()));
                } else {
                    // For non-required equality, use error variables
                    if (constraint.error_variable_ids.plus) |plus_id| {
                        try expr.addTerm(plus_id, -1.0);
                    }
                    if (constraint.error_variable_ids.minus) |minus_id| {
                        try expr.addTerm(minus_id, 1.0);
                    }
                    const basic_var = try self.findOrCreateBasicVariable(&expr);
                    try self.tableau.append(TableauRow.init(basic_var.id, try expr.clone()));
                }
            },
            .less_than_or_equal => {
                // Add slack variable: expr + slack = 0
                if (constraint.slack_variable_id) |slack_id| {
                    try expr.addTerm(slack_id, 1.0);
                }
                const basic_var = try self.findOrCreateBasicVariable(&expr);
                try self.tableau.append(TableauRow.init(basic_var.id, try expr.clone()));
            },
            .greater_than_or_equal => {
                // Add slack variable: expr - slack = 0
                if (constraint.slack_variable_id) |slack_id| {
                    try expr.addTerm(slack_id, -1.0);
                }
                const basic_var = try self.findOrCreateBasicVariable(&expr);
                try self.tableau.append(TableauRow.init(basic_var.id, try expr.clone()));
            },
        }
    }

    fn findOrCreateBasicVariable(self: *ConstraintSolver, expression: *Expression) !*Variable {
        // Try to find a suitable basic variable from the expression
        for (expression.terms.items) |term| {
            if (self.variables.get(term.variable_id)) |variable| {
                if (!variable.is_external and !variable.is_basic) {
                    variable.is_basic = true;
                    return variable;
                }
            }
        }

        // Create a new artificial variable if needed
        const artificial = try self.createVariable("artificial");
        artificial.is_external = false;
        artificial.is_basic = true;
        return artificial;
    }

    pub fn solve(self: *ConstraintSolver) !void {
        // Phase 1: Find feasible solution
        try self.findFeasibleSolution();

        // Phase 2: Optimize
        try self.optimize();

        // Update variable values from tableau
        try self.updateVariableValues();
    }

    fn findFeasibleSolution(self: *ConstraintSolver) !void {
        // Implement Phase 1 of simplex algorithm
        // This finds an initial feasible solution by minimizing artificial variables

        var iterations: u32 = 0;
        const max_iterations: u32 = 1000;

        while (iterations < max_iterations) {
            iterations += 1;

            // Find entering variable (most negative reduced cost)
            var entering_var_id: ?u32 = null;
            var min_reduced_cost: f64 = -self.epsilon;

            var var_iter = self.variables.iterator();
            while (var_iter.next()) |entry| {
                const variable = entry.value_ptr.*;
                if (!variable.is_basic) {
                    const reduced_cost = self.calculateReducedCost(variable.id);
                    if (reduced_cost < min_reduced_cost) {
                        min_reduced_cost = reduced_cost;
                        entering_var_id = variable.id;
                    }
                }
            }

            // If no entering variable, we're done
            if (entering_var_id == null) break;

            // Find leaving variable using minimum ratio test
            const leaving_row_index = try self.findLeavingVariable(entering_var_id.?);
            if (leaving_row_index == null) {
                // Unbounded solution
                return error.UnboundedSolution;
            }

            // Perform pivot operation
            try self.pivot(entering_var_id.?, leaving_row_index.?);
        }

        if (iterations >= max_iterations) {
            return error.MaxIterationsExceeded;
        }
    }

    fn optimize(self: *ConstraintSolver) !void {
        // Phase 2: Optimize the objective function
        var iterations: u32 = 0;
        const max_iterations: u32 = 1000;

        while (iterations < max_iterations) {
            iterations += 1;

            // Find entering variable (most negative coefficient in objective row)
            var entering_var_id: ?u32 = null;
            var min_coefficient: f64 = -self.epsilon;

            for (self.objective_row.terms.items) |term| {
                if (term.coefficient < min_coefficient) {
                    if (self.variables.get(term.variable_id)) |variable| {
                        if (!variable.is_basic) {
                            min_coefficient = term.coefficient;
                            entering_var_id = term.variable_id;
                        }
                    }
                }
            }

            // If no entering variable, we're optimal
            if (entering_var_id == null) break;

            // Find leaving variable
            const leaving_row_index = try self.findLeavingVariable(entering_var_id.?);
            if (leaving_row_index == null) {
                return error.UnboundedSolution;
            }

            // Perform pivot
            try self.pivot(entering_var_id.?, leaving_row_index.?);
        }

        if (iterations >= max_iterations) {
            return error.MaxIterationsExceeded;
        }
    }

    fn calculateReducedCost(self: *const ConstraintSolver, variable_id: u32) f64 {
        // Calculate reduced cost for a non-basic variable
        var cost: f64 = 0.0;

        // Check objective row
        for (self.objective_row.terms.items) |term| {
            if (term.variable_id == variable_id) {
                cost = term.coefficient;
                break;
            }
        }

        // Subtract contributions from basic variables
        for (self.tableau.items, 0..) |row, i| {
            _ = i;
            for (row.expression.terms.items) |term| {
                if (term.variable_id == variable_id) {
                    // Find objective coefficient for basic variable
                    var basic_obj_coeff: f64 = 0.0;
                    for (self.objective_row.terms.items) |obj_term| {
                        if (obj_term.variable_id == row.basic_variable_id) {
                            basic_obj_coeff = obj_term.coefficient;
                            break;
                        }
                    }
                    cost -= term.coefficient * basic_obj_coeff;
                }
            }
        }

        return cost;
    }

    fn findLeavingVariable(self: *const ConstraintSolver, entering_var_id: u32) !?usize {
        var min_ratio: f64 = math.inf(f64);
        var leaving_row: ?usize = null;

        for (self.tableau.items, 0..) |row, i| {
            // Find coefficient of entering variable in this row
            var coefficient: f64 = 0.0;
            for (row.expression.terms.items) |term| {
                if (term.variable_id == entering_var_id) {
                    coefficient = term.coefficient;
                    break;
                }
            }

            // Skip if coefficient is non-positive
            if (coefficient <= self.epsilon) continue;

            // Calculate ratio
            const ratio = -row.expression.constant / coefficient;
            if (ratio >= 0 and ratio < min_ratio) {
                min_ratio = ratio;
                leaving_row = i;
            }
        }

        return leaving_row;
    }

    fn pivot(self: *ConstraintSolver, entering_var_id: u32, leaving_row_index: usize) !void {
        // Get the leaving row
        var leaving_row = &self.tableau.items[leaving_row_index];

        // Find coefficient of entering variable in leaving row
        var pivot_coeff: f64 = 0.0;
        var pivot_term_index: ?usize = null;
        for (leaving_row.expression.terms.items, 0..) |term, j| {
            if (term.variable_id == entering_var_id) {
                pivot_coeff = term.coefficient;
                pivot_term_index = j;
                break;
            }
        }

        if (@abs(pivot_coeff) < self.epsilon) {
            return error.NumericalInstability;
        }

        // Update basic variable status
        if (self.variables.get(leaving_row.basic_variable_id)) |old_basic| {
            old_basic.is_basic = false;
            old_basic.row_index = null;
        }
        if (self.variables.get(entering_var_id)) |new_basic| {
            new_basic.is_basic = true;
            new_basic.row_index = leaving_row_index;
        }

        // Normalize the pivot row
        leaving_row.expression.multiply(1.0 / pivot_coeff);
        if (pivot_term_index) |index| {
            _ = leaving_row.expression.terms.orderedRemove(index);
        }

        // Update basic variable
        leaving_row.basic_variable_id = entering_var_id;

        // Update other tableau rows
        for (self.tableau.items, 0..) |*row, i| {
            if (i == leaving_row_index) continue;

            // Find coefficient of entering variable in this row
            var coeff: f64 = 0.0;
            var term_index: ?usize = null;
            for (row.expression.terms.items, 0..) |term, j| {
                if (term.variable_id == entering_var_id) {
                    coeff = term.coefficient;
                    term_index = j;
                    break;
                }
            }

            if (@abs(coeff) < self.epsilon) continue;

            // Eliminate entering variable from this row
            for (leaving_row.expression.terms.items) |term| {
                try row.expression.addTerm(term.variable_id, -coeff * term.coefficient);
            }
            row.expression.addConstant(-coeff * leaving_row.expression.constant);

            // Remove the entering variable term
            if (term_index) |index| {
                _ = row.expression.terms.orderedRemove(index);
            }
        }

        // Update objective row
        var obj_coeff: f64 = 0.0;
        var obj_term_index: ?usize = null;
        for (self.objective_row.terms.items, 0..) |term, j| {
            if (term.variable_id == entering_var_id) {
                obj_coeff = term.coefficient;
                obj_term_index = j;
                break;
            }
        }

        if (@abs(obj_coeff) > self.epsilon) {
            for (leaving_row.expression.terms.items) |term| {
                try self.objective_row.addTerm(term.variable_id, -obj_coeff * term.coefficient);
            }
            self.objective_row.addConstant(-obj_coeff * leaving_row.expression.constant);

            if (obj_term_index) |index| {
                _ = self.objective_row.terms.orderedRemove(index);
            }
        }
    }

    fn updateVariableValues(self: *ConstraintSolver) !void {
        // Set all non-basic variables to 0
        var var_iter = self.variables.iterator();
        while (var_iter.next()) |entry| {
            const variable = entry.value_ptr.*;
            if (!variable.is_basic) {
                variable.value = 0.0;
            }
        }

        // Calculate values for basic variables
        for (self.tableau.items) |row| {
            if (self.variables.get(row.basic_variable_id)) |basic_var| {
                basic_var.value = -row.expression.constant;

                // Subtract contributions from non-basic variables
                for (row.expression.terms.items) |term| {
                    if (self.variables.get(term.variable_id)) |var_ptr| {
                        if (!var_ptr.is_basic) {
                            basic_var.value -= term.coefficient * var_ptr.value;
                        }
                    }
                }
            }
        }
    }

    pub fn getVariableValue(_: *const ConstraintSolver, variable: *const Variable) f64 {
        return variable.value;
    }

    pub fn suggestValue(self: *ConstraintSolver, variable: *Variable, value: f64) !void {
        // Add a strong constraint suggesting this value
        var expr = Expression.init(self.allocator);
        defer expr.deinit();

        try expr.addTerm(variable.id, 1.0);
        expr.addConstant(-value);

        try self.addConstraint(try expr.clone(), .equal, .medium);
    }

    /// Integration hook for layout system
    pub fn createLayoutConstraints(self: *ConstraintSolver, layout_spec: LayoutSpecification) !void {
        // Create variables for each UI element
        for (layout_spec.elements) |element| {
            const x = try self.createVariable(try std.fmt.allocPrint(self.allocator, "{s}.x", .{element.name}));
            const y = try self.createVariable(try std.fmt.allocPrint(self.allocator, "{s}.y", .{element.name}));
            const width = try self.createVariable(try std.fmt.allocPrint(self.allocator, "{s}.width", .{element.name}));
            const height = try self.createVariable(try std.fmt.allocPrint(self.allocator, "{s}.height", .{element.name}));

            element.variables = .{
                .x = x,
                .y = y,
                .width = width,
                .height = height,
            };

            // Add minimum size constraints
            if (element.min_width) |min_w| {
                var expr = Expression.init(self.allocator);
                try expr.addTerm(width.id, 1.0);
                expr.addConstant(-min_w);
                try self.addConstraint(expr, .greater_than_or_equal, .required);
            }

            if (element.min_height) |min_h| {
                var expr = Expression.init(self.allocator);
                try expr.addTerm(height.id, 1.0);
                expr.addConstant(-min_h);
                try self.addConstraint(expr, .greater_than_or_equal, .required);
            }
        }

        // Add layout-specific constraints
        try layout_spec.applyConstraints(self);
    }
};

/// Layout element for UI components
pub const LayoutElement = struct {
    name: []const u8,
    min_width: ?f64,
    min_height: ?f64,
    max_width: ?f64,
    max_height: ?f64,
    variables: ?struct {
        x: *Variable,
        y: *Variable,
        width: *Variable,
        height: *Variable,
    },
};

/// Layout constraint for positioning
pub const LayoutConstraint = struct {
    constraint_type: ConstraintType,
    elements: []const []const u8,
    alignment: ?Alignment,
    distribution: ?Distribution,
    relative_offset: ?f64,
    relative_relation: ?Relation,
    fixed_value: ?f64,

    pub const ConstraintType = enum {
        alignment,
        distribution,
        relative_position,
        fixed_size,
    };

    pub const Alignment = enum {
        left,
        right,
        top,
        bottom,
        center_horizontal,
        center_vertical,
    };

    pub const Distribution = enum {
        horizontal,
        vertical,
        grid,
    };
};

/// Layout specification for integration
pub const LayoutSpecification = struct {
    elements: []LayoutElement,
    constraints: []LayoutConstraint,

    pub fn applyConstraints(self: *const LayoutSpecification, solver: *ConstraintSolver) !void {
        for (self.constraints) |constraint| {
            switch (constraint.constraint_type) {
                .alignment => try self.applyAlignmentConstraint(solver, constraint),
                .distribution => try self.applyDistributionConstraint(solver, constraint),
                .relative_position => try self.applyRelativeConstraint(solver, constraint),
                .fixed_size => try self.applyFixedConstraint(solver, constraint),
            }
        }
    }

    fn applyAlignmentConstraint(self: *const LayoutSpecification, solver: *ConstraintSolver, constraint: LayoutConstraint) !void {
        _ = self;
        _ = solver;
        _ = constraint;
        // Implementation for alignment constraints
        // This would create equality constraints between appropriate element properties
    }

    fn applyDistributionConstraint(self: *const LayoutSpecification, solver: *ConstraintSolver, constraint: LayoutConstraint) !void {
        _ = self;
        _ = solver;
        _ = constraint;
        // Implementation for distribution constraints
        // This would create spacing constraints between elements
    }

    fn applyRelativeConstraint(self: *const LayoutSpecification, solver: *ConstraintSolver, constraint: LayoutConstraint) !void {
        _ = self;
        _ = solver;
        _ = constraint;
        // Implementation for relative positioning constraints
    }

    fn applyFixedConstraint(self: *const LayoutSpecification, solver: *ConstraintSolver, constraint: LayoutConstraint) !void {
        _ = self;
        _ = solver;
        _ = constraint;
        // Implementation for fixed value constraints
    }
};

// Tests
test "basic constraint solver" {
    var solver = ConstraintSolver.init(testing.allocator);
    defer solver.deinit();

    // Create variables
    const x = try solver.createVariable("x");
    const y = try solver.createVariable("y");

    // Add constraints: x + y = 10, x >= 3, y >= 2
    var expr1 = Expression.init(testing.allocator);
    try expr1.addTerm(x.id, 1.0);
    try expr1.addTerm(y.id, 1.0);
    expr1.addConstant(-10.0);
    try solver.addConstraint(expr1, .equal, .required);

    var expr2 = Expression.init(testing.allocator);
    try expr2.addTerm(x.id, 1.0);
    expr2.addConstant(-3.0);
    try solver.addConstraint(expr2, .greater_than_or_equal, .required);

    var expr3 = Expression.init(testing.allocator);
    try expr3.addTerm(y.id, 1.0);
    expr3.addConstant(-2.0);
    try solver.addConstraint(expr3, .greater_than_or_equal, .required);

    // Solve
    try solver.solve();

    // Check solution
    const x_value = solver.getVariableValue(x);
    const y_value = solver.getVariableValue(y);

    try testing.expectApproxEqAbs(x_value + y_value, 10.0, 0.001);
    try testing.expect(x_value >= 3.0 - 0.001);
    try testing.expect(y_value >= 2.0 - 0.001);
}

test "constraint priorities" {
    var solver = ConstraintSolver.init(testing.allocator);
    defer solver.deinit();

    const x = try solver.createVariable("x");

    // Add conflicting constraints with different priorities
    var expr1 = Expression.init(testing.allocator);
    try expr1.addTerm(x.id, 1.0);
    expr1.addConstant(-10.0);
    try solver.addConstraint(expr1, .equal, .weak);

    var expr2 = Expression.init(testing.allocator);
    try expr2.addTerm(x.id, 1.0);
    expr2.addConstant(-5.0);
    try solver.addConstraint(expr2, .equal, .strong);

    try solver.solve();

    // Should prefer the strong constraint
    const x_value = solver.getVariableValue(x);
    try testing.expectApproxEqAbs(x_value, 5.0, 0.1);
}

test "UI layout example" {
    var solver = ConstraintSolver.init(testing.allocator);
    defer solver.deinit();

    // Create variables for a simple two-panel layout
    const left_x = try solver.createVariable("left.x");
    const left_width = try solver.createVariable("left.width");
    const right_x = try solver.createVariable("right.x");
    const right_width = try solver.createVariable("right.width");
    const container_width = try solver.createVariable("container.width");

    // Container width = 100
    var container_expr = Expression.init(testing.allocator);
    try container_expr.addTerm(container_width.id, 1.0);
    container_expr.addConstant(-100.0);
    try solver.addConstraint(container_expr, .equal, .required);

    // Left panel starts at x=0
    var left_start = Expression.init(testing.allocator);
    try left_start.addTerm(left_x.id, 1.0);
    try solver.addConstraint(left_start, .equal, .required);

    // Right panel starts where left panel ends
    var panels_touch = Expression.init(testing.allocator);
    try panels_touch.addTerm(right_x.id, 1.0);
    try panels_touch.addTerm(left_x.id, -1.0);
    try panels_touch.addTerm(left_width.id, -1.0);
    try solver.addConstraint(panels_touch, .equal, .required);

    // Right panel ends at container width
    var right_end = Expression.init(testing.allocator);
    try right_end.addTerm(right_x.id, 1.0);
    try right_end.addTerm(right_width.id, 1.0);
    try right_end.addTerm(container_width.id, -1.0);
    try solver.addConstraint(right_end, .equal, .required);

    // Prefer equal widths (medium priority)
    var equal_widths = Expression.init(testing.allocator);
    try equal_widths.addTerm(left_width.id, 1.0);
    try equal_widths.addTerm(right_width.id, -1.0);
    try solver.addConstraint(equal_widths, .equal, .medium);

    // Minimum widths
    var left_min = Expression.init(testing.allocator);
    try left_min.addTerm(left_width.id, 1.0);
    left_min.addConstant(-20.0);
    try solver.addConstraint(left_min, .greater_than_or_equal, .required);

    var right_min = Expression.init(testing.allocator);
    try right_min.addTerm(right_width.id, 1.0);
    right_min.addConstant(-20.0);
    try solver.addConstraint(right_min, .greater_than_or_equal, .required);

    // Solve the layout
    try solver.solve();

    // Check the solution
    try testing.expectApproxEqAbs(solver.getVariableValue(left_x), 0.0, 0.001);
    try testing.expectApproxEqAbs(solver.getVariableValue(left_width), 50.0, 0.001);
    try testing.expectApproxEqAbs(solver.getVariableValue(right_x), 50.0, 0.001);
    try testing.expectApproxEqAbs(solver.getVariableValue(right_width), 50.0, 0.001);
}
