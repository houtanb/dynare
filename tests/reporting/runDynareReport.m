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

shortNames = {'US', 'EU', 'JA', 'EA6', 'LA6', 'RC6'};
longNames  = {'Coca Cola', 'Kinder Bueno', 'Pizza', ...
              'Vegetarianism Is Good', 'OS X', 'Dothraki'};

%% Begin Report
rep = report();


%% Country Pages
i=1;
rep = rep.addPage('title', {'Jan1 vs Jan2', longNames{i}}, ...
                  'titleFormat', {'\large\bfseries', '\large'});
rep = rep.addSection('cols', 2);
rep = CountryGraphPage(rep, shortNames{i}, db_q, dc_q, prange, srange);


%% Write & Compile Report
rep.write();
rep.compile();
toc
end