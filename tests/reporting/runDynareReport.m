function runDynareReport(dc_a, dc_q, db_a, db_q)
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

startpoint = strings(prange(1));
shaded = strings(srange(1));
endpoint = strings(prange(end));

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
rep = rep.addTable('title', {'Real GDP Growth','subtitle 1', 'subtitle 2'}, ...
                   'range', larange, ...
                   'vlineAfter', dates('2011y'));
rep = AnnualTable(rep, db_a, dc_a, 'PCH_GROWTH4_', larange);
rep = rep.addVspace('number', 2);

% Table 2
rep = rep.addTable('title', 'Potential GDP Growth', 'range', larange, ...
                   'vlineAfter', dates('2011y'));
rep = AnnualTable(rep, db_a, dc_a, 'PCH_GROWTH4_BAR_', larange);


%% Country Pages
for i=1:1
    rep = rep.addPage('title', {'Jan1 vs Jan2', longNames{i}}, ...
                      'titleFormat', {'\large\bfseries', '\large'});
    rep = rep.addSection('cols', 5);
    rep = CountryGraphPage(rep, shortNames{i}, db_q, dc_q, prange, srange);

    rep = rep.addPage('title', 'Jan1 vs Jan2', ...
                      'titleFormat', '\large\bfseries');
    rep = rep.addSection();
    rep = CountryTablePage(rep, shortNames{i}, longNames{i}, db_q, dc_q, ...
                           db_a, dc_a, trange, dates('2012q2'));
end

%% Write & Compile Report
rep.write();
rep.compile();
toc
end