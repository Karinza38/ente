import { Box } from '@mui/material';
import { styled } from '@mui/material';

const VerticallyCentered = styled(Box)`
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    flex-direction: column;
    text-align: center;
    overflow: auto;
`;

export default VerticallyCentered;

export const DisclaimerContainer = styled('div')`
    margin: 16px 0;
    color: rgb(158, 150, 137);
    font-size: 14px;
`;

export const Row = styled('div')`
    min-height: 32px;
    display: flex;
    align-items: center;
    margin-bottom: ${({ theme }) => theme.spacing(2)};
    flex: 1;
`;

export const Label = styled('div')<{ width?: string }>`
    width: ${(props) => props.width ?? '70%'};
    color: ${(props) => props.theme.palette.text.secondary};
`;
export const Value = styled('div')<{ width?: string }>`
    display: flex;
    justify-content: flex-start;
    align-items: center;
    width: ${(props) => props.width ?? '30%'};
`;

export const FlexWrapper = styled(Box)`
    display: flex;
    width: 100%;
    align-items: center;
`;

export const FreeFlowText = styled('div')`
    word-break: break-word;
    min-width: 30%;
    text-align: left;
`;

export const SpaceBetweenFlex = styled(FlexWrapper)`
    justify-content: space-between;
`;

export const CenteredFlex = styled(FlexWrapper)`
    justify-content: center;
`;

export const FluidContainer = styled(FlexWrapper)`
    flex: 1;
`;

export const Overlay = styled(Box)<{ zIndex: number }>`
    display: flex;
    position: absolute;
    width: 100%;
    height: 100%;
    top: 0;
    left: 0;
    z-index: ${({ zIndex }) => zIndex};
`;
