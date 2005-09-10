function marginal = marginal_density()
% stephane.adjemian@ens.fr [09-09-2005]
global M_ options_ estim_params_ oo_

npar = estim_params_.np+estim_params_.nvn+estim_params_.ncx+estim_params_.ncn+estim_params_.nvx;
nblck = options_.mh_nblck;

DirectoryName = CheckPath('metropolis');
load([ DirectoryName '\'  M_.fname '_mh_history'])

FirstMhFile = record.KeepedDraws.FirstMhFile;
FirstLine = record.KeepedDraws.FirstLine; ifil = FirstLine;
TotalNumberOfMhFiles = sum(record.MhDraws(:,2));
TotalNumberOfMhDraws = sum(record.MhDraws(:,1));
MAX_nruns = ceil(options_.MaxNumberOfBytes/(npar+2)/8);
AJETER = floor(options_.mh_drop*TotalNumberOfMhDraws);

MU = zeros(1,npar);
SIGMA = zeros(npar,npar);
lpost_mode = -Inf;

fprintf('MH: I''m computing the posterior mean... ');
for n = FirstMhFile:TotalNumberOfMhFiles
  for b = 1:nblck
    eval(['load ' DirectoryName '\' M_.fname '_mh' int2str(n) '_blck' int2str(b)]);
    MU(1,:) = MU(1,:) + sum(x2(ifil:end,:));
    lpost_mode = max(lpost_mode,max(logpo2));
  end
  ifil = 1;
end
MU = MU/((TotalNumberOfMhDraws-AJETER)*nblck);
%% lpost_mode is the value of the log posterior kernel at the mode.	
fprintf(' Done!\n');
fprintf('MH: I''m computing the posterior covariance matrix... ');
ifil = FirstLine;
for n = FirstMhFile:TotalNumberOfMhFiles
  for b = 1:nblck
    eval(['load ' DirectoryName '\' M_.fname '_mh' int2str(n) '_blck' int2str(b)]);
    SIGMA = SIGMA + (x2(ifil:end,:)-repmat(MU,length(x2(ifil:end,:)),1))'*...
	    (x2(ifil:end,:)-repmat(MU,length(x2(ifil:end,:)),1));
  end
  ifil = 1;
end
SIGMA =  SIGMA/((TotalNumberOfMhDraws-AJETER)*nblck);%<=== Variance of the parameters (ok!)
fprintf(' Done!\n');
disp(' ');
disp('MH: I''m computing the posterior log marginale density (modified harmonic mean)... ');
detSIGMA = det(SIGMA);
invSIGMA = inv(SIGMA);
marginal = zeros(9,2);
linee = 0;
check_coverage = 1;
increase = 1;
while check_coverage
  for p = 0.1:0.1:0.9;
    critval = qchisq(p,npar);
    ifil = FirstLine;
    tmp = 0;
    for n = FirstMhFile:TotalNumberOfMhFiles
      for b=1:nblck
	eval(['load ' DirectoryName '\' M_.fname '_mh' int2str(n) '_blck' int2str(b)]);
	EndOfFile = size(x2,1);
	for i = ifil:EndOfFile
	  deviation  = (x2(i,:)-MU)*invSIGMA*(x2(i,:)-MU)';
	  if deviation <= critval
	    lftheta = -log(p)-(npar*log(2*pi)+log(detSIGMA)+deviation)/2;
	    tmp = tmp + exp(lftheta - logpo2(i) + lpost_mode);
	  end
	end
      end
      ifil = 1;
    end
    linee = linee + 1;
    warning off all
    marginal(linee,:) = [p, lpost_mode-log(tmp/((TotalNumberOfMhDraws-AJETER)*nblck))];
    warning on all
  end
  if abs((marginal(9,2)-marginal(1,2))/marginal(9,2)) > 0.01 | isinf(marginal(1,2))
    if increase == 1
      disp('MH: The support of the weighting density function is not large enough...')
      disp('MH: I increase the variance of this distribution.')
      increase = 1.2*increase;
      invSIGMA = inv(SIGMA*increase);
      detSIGMA = det(SIGMA*increase);
      linee    = 0;   
    else
      disp('MH: Let me try again.')
      increase = 1.2*increase;
      invSIGMA = inv(SIGMA*increase);
      detSIGMA = det(SIGMA*increase);
      linee    = 0;
      if increase > 20
	check_coverage = 0;
	clear invSIGMA detSIGMA increase;
	disp('MH: There''s probably a problem with the modified harmonic mean estimator.')    
      end    
    end    
  else
    check_coverage = 0;
    clear invSIGMA detSIGMA increase;
    disp('MH: Modified harmonic mean estimator, done!')
  end    
end

oo_.MarginalDensity.ModifiedHarmonicMean = mean(marginal(:,2));