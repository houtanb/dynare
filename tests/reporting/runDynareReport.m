function runDynareReport(dc_a, dc_q, db_a, db_q)
%function runDynareReport(dc_a, dc_q, db_a, db_q)

% Copyright (C) 2013-2014 Dynare Team
%
% This file is part of Dynare.
%
% Dynare is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% Dynare is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
%
% You should have received a copy of the GNU General Public License
% along with Dynare.  If not, see <http://www.gnu.org/licenses/>.

tic
larange= dates('2007a'):dates('2014a');
trange = dates('2012q2'):dates('2014q4');
prange = dates('2007q1'):dates('2013q4');
forecast_date = dates('2012q2');
srange = forecast_date:prange(end);

shortNames = {'US', 'EU', 'JA', 'EA6', 'LA6', 'RC6'};
longNames  = {'Coca Cola', 'Kinder Bueno', 'Pizza', ...
              'Vegetarianism Is Good', 'OS X', 'Dothraki'};

%% Begin Report
rep = report();


%% Page 1: GDP
rep = rep.addPage('title', 'Jan1 vs Jan2', ...
                  'titleFormat', '\large\bfseries');
rep = rep.addSection();
rep = rep.addVspace();

% Table 1
rep = rep.addTable('title', 'Real GDP Growth', 'range', larange, ...
                   'vlineAfter', dates('2011y'));
rep = AnnualTable(rep, db_a, dc_a, 'PCH_GROWTH4_', larange);
rep = rep.addVspace('number', 2);

% Table 2
rep = rep.addTable('title', 'Potential GDP Growth', 'range', larange, ...
                   'vlineAfter', dates('2011y'));
rep = AnnualTable(rep, db_a, dc_a, 'PCH_GROWTH4_BAR_', larange);


%% Page 2: Headline & Core Inflation
rep = rep.addPage('title', 'Jan1 vs Jan2', ...
                  'titleFormat', '\large\bfseries');
rep = rep.addSection();
rep = rep.addVspace();

% Table 1
rep = rep.addTable('title', 'Headline CPI Inflation', 'range', larange, ...
                   'vlineAfter', dates('2011y'));
rep = AnnualTable(rep, db_a, dc_a, 'PCH_PIE4_', larange);
rep = rep.addVspace('number', 2);

% Table 2
rep = rep.addTable('title', 'Core CPI Inflation', 'range', larange, ...
                   'vlineAfter', dates('2011y'));
rep = AnnualTable(rep, db_a, dc_a, 'PCH_PIEX4_', larange);


%% Page 3: Gas & Food Inflation
rep = rep.addPage('title', 'Jan1 vs Jan2', ...
                  'titleFormat', '\large\bfseries');
rep = rep.addSection();
rep = rep.addVspace();

% Table 1
rep = rep.addTable('title', 'Gas Inflation', 'range', larange, ...
                   'vlineAfter', dates('2011y'));
rep = AnnualTable(rep, db_a, dc_a, 'PCH_PIE4_GAS_', larange);
rep = rep.addVspace('number', 2);

% Table 2
rep = rep.addTable('title', 'Food Inflation', 'range', larange, ...
                   'vlineAfter', dates('2011y'));
rep = AnnualTable(rep, db_a, dc_a, 'PCH_PIE4_CONSFOOD_', larange);


%% Page 4: i & Output Gap
rep = rep.addPage('title', 'Jan1 vs Jan2', ...
                  'titleFormat', '\large\bfseries');
rep = rep.addSection();
rep = rep.addVspace();

% Table 1
rep = rep.addTable('title', 'Nominal Interest Rate', 'range', larange, ...
                   'vlineAfter', dates('2011y'));
rep = AnnualTable(rep, db_a, dc_a, 'RS_', larange);
rep = rep.addVspace('number', 2);

% Table 2
rep = rep.addTable('title', 'Output Gap', 'range', larange, ...
                   'vlineAfter', dates('2011y'));
db_a = db_a.tex_rename('Y_WORLD', 'World');
rep = rep.addSeries('data', db_a{'Y_WORLD'});
delta = db_a{'Y_WORLD'}-dc_a{'Y_WORLD'};
delta = delta.tex_rename('$\Delta$');
rep = rep.addSeries('data', delta, ...
                    'tableShowMarkers', true, ...
                    'tableAlignRight', true);
rep = AnnualTable(rep, db_a, dc_a, 'Y_', larange);

%% Country Pages
for i=1:length(shortNames)
    rep = rep.addPage('title', {'Jan1 vs Jan2', longNames{i}}, ...
                      'titleFormat', {'\large\bfseries', '\large'});
    rep = rep.addSection('cols', 2);
    rep = CountryGraphPage(rep, shortNames{i}, db_q, dc_q, prange, srange);

    rep = rep.addPage('title', 'Jan1 vs Jan2', ...
                      'titleFormat', '\large\bfseries');
    rep = rep.addSection();
    rep = CountryTablePage(rep, shortNames{i}, longNames{i}, db_q, dc_q, ...
                           db_a, dc_a, trange, dates('2012q2'));
end

%% Residual Reports
% Countries
for i=1:length(shortNames)
    rep = rep.addPage('title', 'Residual Report Jan1 vs Jan2', ...
                      'titleFormat', '\large\bfseries');
    rep = rep.addSection();
    rep = ResidTablePage(rep, shortNames{i}, longNames{i}, db_q, dc_q, trange, dates('2012q2'));
end

% Commodities
rep = rep.addPage('title', 'Residual Report Jan1 vs Jan2', ...
                  'titleFormat', '\large\bfseries');
rep = rep.addSection();
rep = CommResidTablePage(rep, db_q, dc_q, trange, dates('2012q2'));

%% Commodities Graphs
%Page 1
rep = rep.addPage('title', 'Jan1 vs Jan2', ...
                  'titleFormat', '\large\bfseries');
rep = rep.addSection('height', '60mm');

rep = rep.addGraph('title', 'World Real Oil Price Index', ...
                   'xrange', prange, ...
                   'shade', srange, ...
                   'showLegend', true);
db_q = db_q.tex_rename('LRPOIL_WORLD', 'Oil Price');
rep = rep.addSeries('data', db_q{'LRPOIL_WORLD'}, ...
                    'graphLineColor', 'blue', ...
                    'graphLineWidth', 'semithick');
db_q = db_q.tex_rename('LRPOIL_BAR_WORLD', 'Equilibrium Oil Price');
rep = rep.addSeries('data', db_q{'LRPOIL_BAR_WORLD'}, ...
                    'graphLineColor', 'green', ...
                    'graphLineStyle', 'solid', ...
                    'graphLineWidth', 'semithick');


rep = rep.addGraph('title', 'World Real Food Price Index', ...
                   'xrange', prange, ...
                   'shade', srange, ...
                   'showLegend', true);
db_q = db_q.tex_rename('LRPFOOD_WORLD', 'Food Price');
rep = rep.addSeries('data', db_q{'LRPFOOD_WORLD'}, ...
                    'graphLineColor', 'blue', ...
                    'graphLineWidth', 'semithick');
db_q = db_q.tex_rename('LRPFOOD_BAR_WORLD', 'Equilibrium Food Price');
rep = rep.addSeries('data', db_q{'LRPFOOD_BAR_WORLD'}, ...
                    'graphLineColor', 'green', ...
                    'graphLineStyle', 'solid', ...
                    'graphLineWidth', 'semithick');

% Pae 2
rep = rep.addPage('title', {'Jan1 vs Jan2', 'World Oil and Food Prices'}, ...
                  'titleFormat', {'\large\bfseries', '\large'});
rep = rep.addSection('cols', 2);


rep = rep.addGraph('title', 'World Real Oil Price', ...
                   'xrange', prange, ...
                   'shade', srange, ...
                   'showLegend', true);
rep = rep.addSeries('data', db_q{'LRPOIL_WORLD'}, ...
                    'graphLineColor', 'blue', ...
                    'graphLineWidth', 'semithick');
rep = rep.addSeries('data', dc_q{'LRPOIL_WORLD'}, ...
                    'graphLineColor', 'blue', ...
                    'graphLineStyle', 'dashed', ...
                    'graphLineWidth', 'semithick');

rep = rep.addGraph('title', 'Equilibrium World Real Oil Price', ...
                   'xrange', prange, ...
                   'shade', srange, ...
                   'showLegend', true);
rep = rep.addSeries('data', db_q{'LRPOIL_BAR_WORLD'}, ...
                    'graphLineColor', 'blue', ...
                    'graphLineWidth', 'semithick');
rep = rep.addSeries('data', dc_q{'LRPOIL_BAR_WORLD'}, ...
                    'graphLineColor', 'blue', ...
                    'graphLineStyle', 'dashed', ...
                    'graphLineWidth', 'semithick');

rep = rep.addGraph('title', 'World Real Food Price', ...
                   'xrange', prange, ...
                   'shade', srange, ...
                   'showLegend', true);
rep = rep.addSeries('data', db_q{'LRPFOOD_WORLD'}, ...
                    'graphLineColor', 'blue', ...
                    'graphLineWidth', 'semithick');
rep = rep.addSeries('data', dc_q{'LRPFOOD_WORLD'}, ...
                    'graphLineColor', 'blue', ...
                    'graphLineStyle', 'dashed', ...
                    'graphLineWidth', 'semithick');

rep = rep.addGraph('title', 'Equilibrium World Real Food Price', ...
                   'xrange', prange, ...
                   'shade', srange, ...
                   'showLegend', true);
rep = rep.addSeries('data', db_q{'LRPFOOD_BAR_WORLD'}, ...
                    'graphLineColor', 'blue', ...
                    'graphLineWidth', 'semithick');
rep = rep.addSeries('data', dc_q{'LRPFOOD_BAR_WORLD'}, ...
                    'graphLineColor', 'blue', ...
                    'graphLineStyle', 'dashed', ...
                    'graphLineWidth', 'semithick');

%% Write & Compile Report
rep.write();
rep.compile();
toc
end